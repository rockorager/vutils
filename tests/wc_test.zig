//! wc integration tests
//! Validates output matches GNU/BSD wc behavior

const std = @import("std");
const testing = std.testing;

const WC_PATH = "zig-out/bin/vwc";

fn runWc(args: []const []const u8) ![]const u8 {
    var argv_buf: [32][]const u8 = undefined;
    argv_buf[0] = WC_PATH;
    for (args, 1..) |arg, i| {
        argv_buf[i] = arg;
    }

    const result = std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = argv_buf[0 .. args.len + 1],
    }) catch |err| {
        std.debug.print("Failed to run wc: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("wc failed: {}\nstderr: {s}\n", .{ result.term, result.stderr });
        return error.WcFailed;
    }

    return result.stdout;
}

fn expectOutput(expected: []const u8, args: []const []const u8) !void {
    const stdout = try runWc(args);
    defer testing.allocator.free(stdout);
    try testing.expectEqualStrings(expected, stdout);
}

// ============================================================================
// Basic functionality tests
// ============================================================================

test "single file - lorem_ipsum.txt" {
    try expectOutput("      13     109     772 tests/fixtures/lorem_ipsum.txt\n", &.{"tests/fixtures/lorem_ipsum.txt"});
}

test "lines only -l" {
    try expectOutput("      13  tests/fixtures/lorem_ipsum.txt\n", &.{ "-l", "tests/fixtures/lorem_ipsum.txt" });
}

test "words only -w" {
    try expectOutput("    109  tests/fixtures/lorem_ipsum.txt\n", &.{ "-w", "tests/fixtures/lorem_ipsum.txt" });
}

test "bytes only -c" {
    try expectOutput("    772 tests/fixtures/lorem_ipsum.txt\n", &.{ "-c", "tests/fixtures/lorem_ipsum.txt" });
}

test "lines and words -lw" {
    try expectOutput("      13     109  tests/fixtures/lorem_ipsum.txt\n", &.{ "-lw", "tests/fixtures/lorem_ipsum.txt" });
}

// ============================================================================
// Edge cases
// ============================================================================

test "empty input" {
    const empty_path = "tests/fixtures/empty.txt";
    {
        const f = try std.fs.cwd().createFile(empty_path, .{});
        f.close();
    }
    defer std.fs.cwd().deleteFile(empty_path) catch {};

    try expectOutput("       0       0       0 tests/fixtures/empty.txt\n", &.{empty_path});
}

test "no trailing newline" {
    const path = "tests/fixtures/no_newline.txt";
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll("hello world");
    }
    defer std.fs.cwd().deleteFile(path) catch {};

    // 0 lines (no newline), 2 words, 11 bytes
    try expectOutput("       0       2      11 tests/fixtures/no_newline.txt\n", &.{path});
}

test "only newlines" {
    const path = "tests/fixtures/only_newlines.txt";
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll("\n\n\n\n\n");
    }
    defer std.fs.cwd().deleteFile(path) catch {};

    // 5 lines, 0 words, 5 bytes
    try expectOutput("       5       0       5 tests/fixtures/only_newlines.txt\n", &.{path});
}

test "single word with newline" {
    const path = "tests/fixtures/single_word.txt";
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll("hello\n");
    }
    defer std.fs.cwd().deleteFile(path) catch {};

    try expectOutput("       1       1       6 tests/fixtures/single_word.txt\n", &.{path});
}

test "multiple spaces between words" {
    const path = "tests/fixtures/multi_space.txt";
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll("hello    world\n");
    }
    defer std.fs.cwd().deleteFile(path) catch {};

    // Still 2 words despite multiple spaces
    try expectOutput("       1       2      15 tests/fixtures/multi_space.txt\n", &.{path});
}

test "tabs as whitespace" {
    const path = "tests/fixtures/tabs.txt";
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll("hello\tworld\n");
    }
    defer std.fs.cwd().deleteFile(path) catch {};

    try expectOutput("       1       2      12 tests/fixtures/tabs.txt\n", &.{path});
}

// ============================================================================
// Multiple files
// ============================================================================

test "multiple files" {
    // Multiple files: should show each file plus total
    const stdout = try runWc(&.{
        "tests/fixtures/lorem_ipsum.txt",
        "tests/fixtures/UTF_8_weirdchars.txt",
    });
    defer testing.allocator.free(stdout);
    
    // Just verify total line is present (exact counts depend on locale)
    try testing.expect(std.mem.indexOf(u8, stdout, "total") != null);
}

// ============================================================================
// Large file tests
// ============================================================================

test "large file" {
    const path = "tests/fixtures/large.txt";
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        // Write 10000 lines of "word word word\n"
        const line = "word word word\n";
        for (0..10000) |_| {
            try f.writeAll(line);
        }
    }
    defer std.fs.cwd().deleteFile(path) catch {};

    // 10000 lines, 30000 words, 150000 bytes
    try expectOutput("   10000   30000  150000 tests/fixtures/large.txt\n", &.{path});
}
