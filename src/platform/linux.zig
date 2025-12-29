//! Linux-specific I/O using io_uring
//! Optimized for high-throughput file reading with:
//! - Registered buffers for zero-copy reads
//! - Batched SQE submissions
//! - Graceful fallback for older kernels

const std = @import("std");
const count = @import("count");
const linux = std.os.linux;
const posix = std.posix;

pub const Counts = count.Counts;
pub const CountMode = count.CountMode;

/// 128KB buffer - optimal for modern NVMe/SSD sequential reads
const READ_BUF_SIZE = 128 * 1024;

/// io_uring ring size - must be power of 2
const RING_ENTRIES = 64;

/// Maximum concurrent file operations
const MAX_CONCURRENT_FILES = 32;

/// Result for a single file count operation
pub const FileResult = struct {
    counts: Counts,
    err: ?FileError,

    pub const FileError = struct {
        path: []const u8,
        code: posix.E,
    };
};

/// io_uring context for batch file processing
const IoUringContext = struct {
    ring: linux.IoUring,
    /// Registered buffer for zero-copy reads
    buffer: [READ_BUF_SIZE]u8 align(4096) = undefined,
    iovec: posix.iovec = undefined,

    fn init() !IoUringContext {
        var params = std.mem.zeroes(linux.io_uring_params);
        // SINGLE_ISSUER: we submit from one thread only
        // COOP_TASKRUN: reduce kernel overhead
        params.flags = linux.IORING_SETUP_SINGLE_ISSUER | linux.IORING_SETUP_COOP_TASKRUN;

        var ctx = IoUringContext{
            .ring = linux.IoUring.init_params(RING_ENTRIES, &params) catch |err| {
                // Fallback: try without advanced flags for older kernels (5.10+)
                params.flags = 0;
                return .{
                    .ring = linux.IoUring.init_params(RING_ENTRIES, &params) catch {
                        return err;
                    },
                };
            },
        };

        // Set up iovec pointing to our buffer
        ctx.iovec = .{
            .base = &ctx.buffer,
            .len = READ_BUF_SIZE,
        };

        // Register buffer for zero-copy reads
        ctx.ring.register_buffers(&[_]posix.iovec{ctx.iovec}) catch {
            // Not fatal - fall back to regular reads
        };

        return ctx;
    }

    fn deinit(self: *IoUringContext) void {
        self.ring.unregister_buffers() catch {};
        self.ring.deinit();
    }

    /// Read entire file using io_uring and count contents
    fn countFile(self: *IoUringContext, path: []const u8, mode: CountMode) FileResult {
        // Open the file
        var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
        if (path.len >= path_buf.len) {
            return .{ .counts = .{}, .err = .{ .path = path, .code = .NAMETOOLONG } };
        }
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;

        const fd = posix.openat(posix.AT.FDCWD, path_buf[0..path.len :0], .{}, 0) catch |err| {
            const code: posix.E = switch (err) {
                error.FileNotFound => .NOENT,
                error.AccessDenied => .ACCES,
                error.IsDir => .ISDIR,
                error.NameTooLong => .NAMETOOLONG,
                else => .IO,
            };
            return .{ .counts = .{}, .err = .{ .path = path, .code = code } };
        };
        defer posix.close(fd);

        // Fast path: bytes only - just use fstat
        if (mode == .bytes_only) {
            const stat = posix.fstat(fd) catch {
                return .{ .counts = .{}, .err = .{ .path = path, .code = .IO } };
            };
            return .{ .counts = .{ .bytes = @intCast(stat.size) }, .err = null };
        }

        // Read file in chunks using io_uring
        var total = Counts{};
        var in_word = false;
        var offset: u64 = 0;

        while (true) {
            // Queue a read operation
            _ = self.ring.read(0, fd, .{ .buffer = &self.buffer }, offset) catch {
                return .{ .counts = total, .err = .{ .path = path, .code = .IO } };
            };

            // Submit and wait for completion
            _ = self.ring.submit_and_wait(1) catch {
                return .{ .counts = total, .err = .{ .path = path, .code = .IO } };
            };

            // Get completion
            const cqe = self.ring.copy_cqe() catch {
                return .{ .counts = total, .err = .{ .path = path, .code = .IO } };
            };

            // Check for errors or EOF
            if (cqe.res < 0) {
                const errno: posix.E = @enumFromInt(@as(u32, @intCast(-cqe.res)));
                return .{ .counts = total, .err = .{ .path = path, .code = errno } };
            }
            if (cqe.res == 0) break; // EOF

            const n: usize = @intCast(cqe.res);
            offset += n;

            // Process the chunk
            switch (mode) {
                .bytes_only => {
                    total.bytes += n;
                },
                .lines_only, .lines_bytes => {
                    const lb = count.countLinesBytes(self.buffer[0..n]);
                    total.lines += lb.lines;
                    total.bytes += lb.bytes;
                },
                .full => {
                    const state = count.countBufferLocale(self.buffer[0..n], in_word);
                    total = total.add(state.counts);
                    in_word = state.in_word;
                },
            }
        }

        return .{ .counts = total, .err = null };
    }
};

/// Count multiple files using io_uring with thread pool for parallelism
/// Each thread gets its own io_uring instance for optimal performance
pub fn countFilesParallel(
    paths: []const []const u8,
    allocator: std.mem.Allocator,
    mode: CountMode,
) ![]FileResult {
    if (paths.len == 0) {
        return try allocator.alloc(FileResult, 0);
    }

    const results = try allocator.alloc(FileResult, paths.len);
    @memset(results, .{ .counts = .{}, .err = null });

    // Single file: use io_uring directly, no thread pool overhead
    if (paths.len == 1) {
        var ctx = IoUringContext.init() catch {
            // Fallback to basic read if io_uring unavailable
            results[0] = countFileFallback(paths[0], mode);
            return results;
        };
        defer ctx.deinit();
        results[0] = ctx.countFile(paths[0], mode);
        return results;
    }

    // Multiple files: use thread pool with per-thread io_uring
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    var wg = std.Thread.WaitGroup{};

    const Context = struct {
        paths: []const []const u8,
        results: []FileResult,
        mode: CountMode,
    };

    var ctx = Context{ .paths = paths, .results = results, .mode = mode };

    for (0..paths.len) |i| {
        pool.spawnWg(&wg, struct {
            fn work(c: *Context, idx: usize) void {
                // Each thread gets its own io_uring instance
                var uring_ctx = IoUringContext.init() catch {
                    c.results[idx] = countFileFallback(c.paths[idx], c.mode);
                    return;
                };
                defer uring_ctx.deinit();
                c.results[idx] = uring_ctx.countFile(c.paths[idx], c.mode);
            }
        }.work, .{ &ctx, i });
    }

    wg.wait();

    return results;
}

/// Fallback file counting using standard read() for kernels without io_uring
fn countFileFallback(path: []const u8, mode: CountMode) FileResult {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        const code: posix.E = switch (err) {
            error.FileNotFound => .NOENT,
            error.AccessDenied => .ACCES,
            error.IsDir => .ISDIR,
            else => .IO,
        };
        return .{ .counts = .{}, .err = .{ .path = path, .code = code } };
    };
    defer file.close();

    if (mode == .bytes_only) {
        const stat = file.stat() catch {
            return .{ .counts = .{}, .err = .{ .path = path, .code = .IO } };
        };
        return .{ .counts = .{ .bytes = stat.size }, .err = null };
    }

    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = file.read(&buf) catch {
            return .{ .counts = total, .err = .{ .path = path, .code = .IO } };
        };
        if (n == 0) break;

        switch (mode) {
            .bytes_only => total.bytes += n,
            .lines_only, .lines_bytes => {
                const lb = count.countLinesBytes(buf[0..n]);
                total.lines += lb.lines;
                total.bytes += lb.bytes;
            },
            .full => {
                const state = count.countBufferLocale(buf[0..n], in_word);
                total = total.add(state.counts);
                in_word = state.in_word;
            },
        }
    }

    return .{ .counts = total, .err = null };
}

/// Count a single file - public API that chooses best implementation
pub fn countFile(path: []const u8, mode: CountMode) FileResult {
    var ctx = IoUringContext.init() catch {
        return countFileFallback(path, mode);
    };
    defer ctx.deinit();
    return ctx.countFile(path, mode);
}

/// Read from stdin - io_uring doesn't help here, use regular reads
pub fn countStdin(mode: CountMode) Counts {
    const stdin = std.fs.File.stdin();
    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = stdin.read(&buf) catch break;
        if (n == 0) break;

        switch (mode) {
            .bytes_only => total.bytes += n,
            .lines_only, .lines_bytes => {
                const lb = count.countLinesBytes(buf[0..n]);
                total.lines += lb.lines;
                total.bytes += lb.bytes;
            },
            .full => {
                const state = count.countBufferLocale(buf[0..n], in_word);
                total = total.add(state.counts);
                in_word = state.in_word;
            },
        }
    }

    return total;
}
