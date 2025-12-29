//! Linux-specific I/O using io_uring
//! Uncompromising platform optimization

const std = @import("std");
const count = @import("count");
const linux = std.os.linux;

pub const Counts = count.Counts;

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
) ![]FileResult {
    if (paths.len == 0) {
        return try allocator.alloc(FileResult, 0);
    }

    const results = try allocator.alloc(FileResult, paths.len);
    @memset(results, .{ .counts = .{}, .err = null });

    if (paths.len == 1) {
        results[0] = countFile(paths[0]);
        return results;
    }

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    var wg = std.Thread.WaitGroup{};

    for (paths, 0..) |path, i| {
        pool.spawnWg(&wg, countFileThread, .{ path, &results[i] });
    }

    wg.wait();

    return results;
}

fn countFileThread(path: []const u8, result: *FileResult) void {
    result.* = countFile(path);
}

/// Count a single file - returns result with optional error
pub fn countFile(path: []const u8) FileResult {
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

    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = file.read(&buf) catch {
            return .{ .counts = total, .err = .{ .path = path, .code = .IO } };
        };
        if (n == 0) break;

        const state = count.countBufferLocale(buf[0..n], in_word);
        total = total.add(state.counts);
        in_word = state.in_word;
    }

    return .{ .counts = total, .err = null };
}

/// Read from stdin
pub fn countStdin() Counts {
    const stdin = std.io.getStdIn();
    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = stdin.read(&buf) catch break;
        if (n == 0) break;

        const state = count.countBufferLocale(buf[0..n], in_word);
        total = total.add(state.counts);
        in_word = state.in_word;
    }

    return total;
}
