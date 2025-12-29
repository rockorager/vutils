//! macOS-specific I/O using Grand Central Dispatch
//! Uncompromising platform optimization

const std = @import("std");
const count = @import("count");
const c = @cImport({
    @cInclude("dispatch/dispatch.h");
    @cInclude("fcntl.h");
    @cInclude("sys/stat.h");
});

pub const Counts = count.Counts;
pub const CountMode = count.CountMode;

const READ_BUF_SIZE = 32 * 1024; // 32KB - optimal based on benchmarking

/// Result for a single file count operation
pub const FileResult = struct {
    counts: Counts,
    err: ?FileError,

    pub const FileError = struct {
        path: []const u8,
        code: std.posix.E,
    };
};

/// Count multiple files in parallel using GCD dispatch_apply
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

    const queue = c.dispatch_get_global_queue(c.QOS_CLASS_USER_INITIATED, 0);

    const Context = struct {
        paths: []const []const u8,
        results: []FileResult,
        mode: CountMode,
    };

    var ctx = Context{ .paths = paths, .results = results, .mode = mode };

    c.dispatch_apply_f(paths.len, queue, &ctx, struct {
        fn work(context: ?*anyopaque, idx: usize) callconv(.c) void {
            const cx: *Context = @ptrCast(@alignCast(context));
            cx.results[idx] = countFile(cx.paths[idx], cx.mode);
        }
    }.work);

    return results;
}

/// Count a single file - returns result with optional error
pub fn countFile(path: []const u8, mode: CountMode) FileResult {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path.len >= path_buf.len) {
        return .{ .counts = .{}, .err = .{ .path = path, .code = .NAMETOOLONG } };
    }
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    const fd = c.open(&path_buf, c.O_RDONLY);
    if (fd < 0) {
        const errno: std.posix.E = @enumFromInt(std.c._errno().*);
        return .{ .counts = .{}, .err = .{ .path = path, .code = errno } };
    }
    defer _ = c.close(fd);

    var st: c.struct_stat = undefined;
    const stat_ok = c.fstat(fd, &st) == 0;

    // Fast path: bytes only - just use fstat, no read needed
    if (mode == .bytes_only and stat_ok) {
        return .{
            .counts = .{ .bytes = @intCast(st.st_size) },
            .err = null,
        };
    }

    // Enable F_NOCACHE for large files
    if (stat_ok and st.st_size > 1024 * 1024) {
        _ = c.fcntl(fd, c.F_NOCACHE, @as(c_int, 1));
    }

    return .{ .counts = countFd(fd, mode), .err = null };
}

fn countFd(fd: c_int, mode: CountMode) Counts {
    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = c.read(fd, &buf, buf.len);
        if (n <= 0) break;

        const slice = buf[0..@intCast(n)];

        switch (mode) {
            .bytes_only => {
                total.bytes += @intCast(n);
            },
            .lines_only, .lines_bytes => {
                const lb = count.countLinesBytes(slice);
                total.lines += lb.lines;
                total.bytes += lb.bytes;
            },
            .full => {
                const state = count.countBufferLocale(slice, in_word);
                total = total.add(state.counts);
                in_word = state.in_word;
            },
        }
    }

    return total;
}

/// Read from stdin
pub fn countStdin(mode: CountMode) Counts {
    return countFd(0, mode);
}
