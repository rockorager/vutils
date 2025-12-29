//! Linux-specific I/O using io_uring
//! Uncompromising platform optimization

const std = @import("std");
const count = @import("count");
const linux = std.os.linux;

pub const Counts = count.Counts;

const READ_BUF_SIZE = 128 * 1024;
const RING_ENTRIES = 256;

/// Count multiple files using io_uring for batched I/O
pub fn countFilesParallel(
    paths: []const []const u8,
    allocator: std.mem.Allocator,
) !Counts {
    if (paths.len == 0) return .{};
    if (paths.len == 1) return try countFile(paths[0], allocator);

    // io_uring approach: batch open + read operations
    // For now, use thread pool - io_uring for file reads is complex
    // TODO: implement proper io_uring batched reads
    
    var ring = try linux.IoUring.init(RING_ENTRIES, 0);
    defer ring.deinit();

    var total = Counts{};
    
    // Simple parallel approach using thread pool
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    const results = try allocator.alloc(Counts, paths.len);
    defer allocator.free(results);
    @memset(results, .{});

    var wg = std.Thread.WaitGroup{};
    
    for (paths, 0..) |path, i| {
        pool.spawnWg(&wg, countFileThread, .{ path, &results[i], allocator });
    }

    wg.wait();

    for (results) |r| {
        total = total.add(r);
    }
    return total;
}

fn countFileThread(path: []const u8, result: *Counts, allocator: std.mem.Allocator) void {
    result.* = countFile(path, allocator) catch .{};
}

/// Count a single file
pub fn countFile(path: []const u8, allocator: std.mem.Allocator) !Counts {
    _ = allocator;
    
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // Use O_DIRECT for large files to bypass page cache
    // (would need aligned buffers - skip for now)

    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;

        const state = count.countBufferWithState(buf[0..n], in_word);
        total = total.add(state.counts);
        in_word = state.in_word;
    }

    return total;
}

/// Read from stdin
pub fn countStdin() !Counts {
    const stdin = std.fs.File.stdin();
    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) break;

        const state = count.countBufferWithState(buf[0..n], in_word);
        total = total.add(state.counts);
        in_word = state.in_word;
    }

    return total;
}
