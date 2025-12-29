//! Benchmark: C locale vs UTF-8 locale whitespace counting
//!
//! Run with: zig build bench

const std = @import("std");
const count = @import("count");

const ITERATIONS = 100;
const WARMUP = 5;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_file = std.fs.File.stdout();
    var stdout_writer = stdout_file.writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    try stdout.print("Generating test data...\n", .{});

    const ascii_text = try generateAsciiText(allocator, 10 * 1024 * 1024);
    defer allocator.free(ascii_text);

    const mixed_text = try generateMixedText(allocator, 10 * 1024 * 1024);
    defer allocator.free(mixed_text);

    const unicode_text = try generateUnicodeHeavyText(allocator, 10 * 1024 * 1024);
    defer allocator.free(unicode_text);

    try stdout.print("\nBenchmark: 10MB buffers, {d} iterations (after {d} warmup)\n\n", .{ ITERATIONS, WARMUP });

    try stdout.print("=== ASCII-heavy text ===\n", .{});
    try benchmarkBoth(stdout, ascii_text);

    try stdout.print("\n=== Mixed UTF-8 text ===\n", .{});
    try benchmarkBoth(stdout, mixed_text);

    try stdout.print("\n=== Unicode-heavy text (CJK/emoji) ===\n", .{});
    try benchmarkBoth(stdout, unicode_text);

    try stdout.flush();
}

fn benchmarkBoth(stdout: *std.Io.Writer, data: []const u8) !void {
    // Warmup
    for (0..WARMUP) |_| {
        _ = count.countBufferWithState(data, false);
        _ = count.countBufferUnicode(data, false);
    }

    // Benchmark C locale
    var c_time: u64 = 0;
    var c_result: count.CountState = undefined;
    for (0..ITERATIONS) |_| {
        var timer = try std.time.Timer.start();
        c_result = count.countBufferWithState(data, false);
        c_time += timer.read();
    }
    const c_avg = c_time / ITERATIONS;

    // Benchmark UTF-8 locale
    var utf8_time: u64 = 0;
    var utf8_result: count.CountState = undefined;
    for (0..ITERATIONS) |_| {
        var timer = try std.time.Timer.start();
        utf8_result = count.countBufferUnicode(data, false);
        utf8_time += timer.read();
    }
    const utf8_avg = utf8_time / ITERATIONS;

    try stdout.print("  C locale:    {d:>8.2}ms  (words={d}, lines={d})\n", .{
        @as(f64, @floatFromInt(c_avg)) / 1_000_000.0,
        c_result.counts.words,
        c_result.counts.lines,
    });
    try stdout.print("  UTF-8:       {d:>8.2}ms  (words={d}, chars={d})\n", .{
        @as(f64, @floatFromInt(utf8_avg)) / 1_000_000.0,
        utf8_result.counts.words,
        utf8_result.counts.chars,
    });

    const ratio = @as(f64, @floatFromInt(utf8_avg)) / @as(f64, @floatFromInt(c_avg));
    if (ratio > 1.05) {
        try stdout.print("  -> C locale is {d:.2}x faster\n", .{ratio});
    } else if (ratio < 0.95) {
        try stdout.print("  -> UTF-8 is {d:.2}x faster\n", .{1.0 / ratio});
    } else {
        try stdout.print("  -> similar performance\n", .{});
    }
}

fn generateAsciiText(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const text = try allocator.alloc(u8, size);
    var rng = std.Random.DefaultPrng.init(42);

    for (text) |*c| {
        const r = rng.random().int(u8) % 100;
        if (r < 70) {
            c.* = 'a' + @as(u8, @intCast(rng.random().int(u8) % 26));
        } else if (r < 85) {
            c.* = ' ';
        } else if (r < 95) {
            c.* = '\n';
        } else {
            c.* = '!' + @as(u8, @intCast(rng.random().int(u8) % 14));
        }
    }
    return text;
}

fn generateMixedText(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(allocator);
    var rng = std.Random.DefaultPrng.init(43);

    while (list.items.len < size) {
        const r = rng.random().int(u8) % 100;
        if (r < 60) {
            try list.append(allocator, 'a' + @as(u8, @intCast(rng.random().int(u8) % 26)));
        } else if (r < 75) {
            try list.append(allocator, ' ');
        } else if (r < 85) {
            try list.append(allocator, '\n');
        } else if (r < 90) {
            try list.append(allocator, 0xC3);
            try list.append(allocator, 0xA0 + @as(u8, @intCast(rng.random().int(u8) % 32)));
        } else if (r < 95) {
            try list.append(allocator, 0xC2);
            try list.append(allocator, 0xA0);
        } else {
            try list.append(allocator, 0xE4);
            try list.append(allocator, 0xB8);
            try list.append(allocator, 0x80 + @as(u8, @intCast(rng.random().int(u8) % 48)));
        }
    }

    return try list.toOwnedSlice(allocator);
}

fn generateUnicodeHeavyText(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(allocator);
    var rng = std.Random.DefaultPrng.init(44);

    while (list.items.len < size) {
        const r = rng.random().int(u8) % 100;
        if (r < 40) {
            try list.append(allocator, 0xE4);
            try list.append(allocator, 0xB8);
            try list.append(allocator, 0x80 + @as(u8, @intCast(rng.random().int(u8) % 48)));
        } else if (r < 60) {
            try list.append(allocator, 0xF0);
            try list.append(allocator, 0x9F);
            try list.append(allocator, 0x98);
            try list.append(allocator, 0x80 + @as(u8, @intCast(rng.random().int(u8) % 32)));
        } else if (r < 70) {
            try list.append(allocator, 0xE2);
            try list.append(allocator, 0x80);
            try list.append(allocator, 0x83);
        } else if (r < 80) {
            try list.append(allocator, ' ');
        } else if (r < 90) {
            try list.append(allocator, '\n');
        } else {
            try list.append(allocator, 0xE3);
            try list.append(allocator, 0x80);
            try list.append(allocator, 0x80);
        }
    }

    return try list.toOwnedSlice(allocator);
}
