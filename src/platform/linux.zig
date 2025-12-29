//! Linux-specific I/O using io_uring
//! Uncompromising platform optimization

const std = @import("std");
const count = @import("count");
const linux = std.os.linux;

pub const Counts = count.Counts;
pub const CountMode = count.CountMode;

const READ_BUF_SIZE = 128 * 1024;
const RING_ENTRIES = 256;

/// Result for a single file count operation
pub const FileResult = struct {
    counts: Counts,
    err: ?FileError,

    pub const FileError = struct {
        path: []const u8,
        code: std.posix.E,
    };
};

/// Count multiple files using thread pool
/// Returns per-file results for individual output
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

    if (paths.len == 1) {
        results[0] = countFile(paths[0], mode);
        return results;
    }

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
                c.results[idx] = countFile(c.paths[idx], c.mode);
            }
        }.work, .{ &ctx, i });
    }

    wg.wait();

    return results;
}

/// Count a single file - returns result with optional error
pub fn countFile(path: []const u8, mode: CountMode) FileResult {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        const code: std.posix.E = switch (err) {
            error.FileNotFound => .NOENT,
            error.AccessDenied => .ACCES,
            error.IsDir => .ISDIR,
            else => .IO,
        };
        return .{ .counts = .{}, .err = .{ .path = path, .code = code } };
    };
    defer file.close();

    // Fast path: bytes only - just use fstat
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
            .bytes_only => {
                total.bytes += n;
            },
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

/// Read from stdin
pub fn countStdin(mode: CountMode) Counts {
    const stdin = std.fs.File.stdin();
    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = stdin.read(&buf) catch break;
        if (n == 0) break;

        switch (mode) {
            .bytes_only => {
                total.bytes += n;
            },
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
