//! vutils wc - POSIX-compliant word count
//! Platform-optimized using GCD (macOS) or io_uring (Linux)

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform");
const Counts = platform.Counts;
const CountMode = platform.CountMode;
const FileResult = platform.FileResult;

const WRITE_BUF_SIZE = if (builtin.os.tag == .macos) 64 * 1024 else 4096;

const Options = struct {
    show_lines: bool = false,
    show_words: bool = false,
    show_bytes: bool = false,
    show_chars: bool = false,
    time_it: bool = false,

    fn anySelected(self: Options) bool {
        return self.show_lines or self.show_words or self.show_bytes or self.show_chars;
    }

    fn showAll(self: *Options) void {
        self.show_lines = true;
        self.show_words = true;
        self.show_bytes = true;
    }

    fn countMode(self: Options) CountMode {
        const needs_words = self.show_words;
        const needs_chars = self.show_chars;
        const needs_lines = self.show_lines;
        const needs_bytes = self.show_bytes;

        if (needs_words or needs_chars) return .full;
        if (needs_lines and needs_bytes) return .lines_bytes;
        if (needs_lines) return .lines_only;
        if (needs_bytes) return .bytes_only;
        return .full;
    }
};

pub fn run() u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    return main(allocator) catch |err| {
        var buf: [WRITE_BUF_SIZE]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buf);
        stderr_writer.interface.print("wc: {s}\n", .{@errorName(err)}) catch {};
        stderr_writer.interface.flush() catch {};
        return 1;
    };
}

fn main(allocator: std.mem.Allocator) !u8 {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var paths: std.ArrayListUnmanaged([]const u8) = .{};
    defer paths.deinit(allocator);

    var opts = Options{};
    var had_error = false;

    var stderr_buf: [WRITE_BUF_SIZE]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            for (arg[1..]) |ch| {
                switch (ch) {
                    'l' => opts.show_lines = true,
                    'w' => opts.show_words = true,
                    'c' => {
                        opts.show_bytes = true;
                        opts.show_chars = false;
                    },
                    'm' => {
                        opts.show_chars = true;
                        opts.show_bytes = false;
                    },
                    't' => opts.time_it = true,
                    else => {
                        stderr.print("wc: invalid option -- '{c}'\n", .{ch}) catch {};
                        stderr.print("Usage: wc [-c|-m] [-lw] [file ...]\n", .{}) catch {};
                        stderr.flush() catch {};
                        return 1;
                    },
                }
            }
        } else {
            try paths.append(allocator, arg);
        }
    }

    if (!opts.anySelected()) {
        opts.showAll();
    }

    const mode = opts.countMode();
    var timer = if (opts.time_it) try std.time.Timer.start() else null;

    var total = Counts{};
    var file_count: usize = 0;
    var stdin_read = false;

    var stdout_buf: [WRITE_BUF_SIZE]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    if (paths.items.len == 0) {
        const counts = platform.countStdin(mode);
        printCounts(stdout, counts, null, opts) catch {};
        total = counts;
        stdin_read = true;
    } else {
        const results = try platform.countFilesParallel(paths.items, allocator, mode);
        defer allocator.free(results);

        for (results, paths.items) |result, path| {
            if (std.mem.eql(u8, path, "-")) {
                if (stdin_read) continue;
                const counts = platform.countStdin(mode);
                printCounts(stdout, counts, "-", opts) catch {};
                total = total.add(counts);
                stdin_read = true;
                file_count += 1;
            } else if (result.err) |err| {
                printFileError(stderr, err.path, err.code);
                had_error = true;
            } else {
                printCounts(stdout, result.counts, path, opts) catch {};
                total = total.add(result.counts);
                file_count += 1;
            }
        }

        if (file_count > 1) {
            printCounts(stdout, total, "total", opts) catch {};
        }
    }

    const elapsed = if (timer) |*t| t.read() else null;

    if (elapsed) |e| {
        stdout.print("Time: {d:.3}ms, Files: {d}\n", .{
            @as(f64, @floatFromInt(e)) / 1_000_000.0,
            file_count,
        }) catch {};
    }

    stdout.flush() catch {};
    stderr.flush() catch {};

    return if (had_error) 1 else 0;
}

fn printCounts(writer: *std.Io.Writer, counts: Counts, name: ?[]const u8, opts: Options) !void {
    // Use width 8 with space separator to match BSD/POSIX format
    if (opts.show_lines) try writer.print("{d:>8} ", .{counts.lines});
    if (opts.show_words) try writer.print("{d:>7} ", .{counts.words});
    if (opts.show_chars) {
        try writer.print("{d:>7}", .{counts.chars});
    } else if (opts.show_bytes) {
        try writer.print("{d:>7}", .{counts.bytes});
    }

    if (name) |n| {
        try writer.print(" {s}", .{n});
    }
    try writer.print("\n", .{});
}

fn printFileError(writer: *std.Io.Writer, path: []const u8, code: std.posix.E) void {
    const msg = switch (code) {
        .NOENT => "No such file or directory",
        .ACCES => "Permission denied",
        .ISDIR => "Is a directory",
        .NAMETOOLONG => "File name too long",
        else => "I/O error",
    };
    writer.print("wc: {s}: {s}\n", .{ path, msg }) catch {};
}
