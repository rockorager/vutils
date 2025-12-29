//! vutils wc - parallel word count
//! Platform-optimized using GCD (macOS) or io_uring (Linux)

const std = @import("std");
const platform = @import("platform");
const Counts = platform.Counts;

/// Entry point for wc tool (called from multicall main)
pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var paths: std.ArrayListUnmanaged([]const u8) = .{};
    defer paths.deinit(allocator);

    var show_lines = false;
    var show_words = false;
    var show_bytes = false;
    var time_it = false;

    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            for (arg[1..]) |ch| {
                switch (ch) {
                    'l' => show_lines = true,
                    'w' => show_words = true,
                    'c' => show_bytes = true,
                    't' => time_it = true,
                    else => {},
                }
            }
        } else {
            try paths.append(allocator, arg);
        }
    }

    // Default: show all
    if (!show_lines and !show_words and !show_bytes) {
        show_lines = true;
        show_words = true;
        show_bytes = true;
    }

    var timer = if (time_it) try std.time.Timer.start() else null;

    const counts = if (paths.items.len == 0)
        try platform.countStdin()
    else
        try platform.countFilesParallel(paths.items, allocator);

    const elapsed = if (timer) |*t| t.read() else null;

    var buf: [4096]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buf);
    const stdout = &file_writer.interface;

    if (show_lines) try stdout.print("{d:>8} ", .{counts.lines});
    if (show_words) try stdout.print("{d:>8} ", .{counts.words});
    if (show_bytes) try stdout.print("{d:>8} ", .{counts.bytes});
    try stdout.print("total\n", .{});

    if (elapsed) |e| {
        try stdout.print("Time: {d:.3}ms, Files: {d}\n", .{
            @as(f64, @floatFromInt(e)) / 1_000_000.0,
            paths.items.len,
        });
    }

    try stdout.flush();
}
