//! vutils echo - POSIX-compliant echo with GNU extensions
//! Supports -n (no newline), -e (escape sequences)

const std = @import("std");
const builtin = @import("builtin");

const WRITE_BUF_SIZE = if (builtin.os.tag == .macos) 64 * 1024 else 4096;

const Options = struct {
    no_newline: bool = false,
    interpret_escapes: bool = false,
};

pub fn run() u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    return main(allocator) catch |err| {
        var buf: [WRITE_BUF_SIZE]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buf);
        stderr_writer.interface.print("echo: {s}\n", .{@errorName(err)}) catch {};
        stderr_writer.interface.flush() catch {};
        return 1;
    };
}

fn main(allocator: std.mem.Allocator) !u8 {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_buf: [WRITE_BUF_SIZE]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    var opts = Options{};
    var arg_start: usize = 1;

    // Parse options (only at the start, before any non-option arguments)
    // Note: GNU echo does NOT recognize -- as option terminator
    while (arg_start < args.len) {
        const arg = args[arg_start];
        if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            // Check if all characters are valid option flags
            var valid = true;
            for (arg[1..]) |ch| {
                if (ch != 'n' and ch != 'e' and ch != 'E') {
                    valid = false;
                    break;
                }
            }
            if (!valid) break;

            for (arg[1..]) |ch| {
                switch (ch) {
                    'n' => opts.no_newline = true,
                    'e' => opts.interpret_escapes = true,
                    'E' => opts.interpret_escapes = false,
                    else => unreachable,
                }
            }
            arg_start += 1;
        } else {
            break;
        }
    }

    // Output arguments
    var first = true;
    for (args[arg_start..]) |arg| {
        if (!first) {
            stdout.print(" ", .{}) catch {};
        }
        first = false;

        if (opts.interpret_escapes) {
            writeEscaped(stdout, arg) catch {};
        } else {
            stdout.print("{s}", .{arg}) catch {};
        }
    }

    if (!opts.no_newline) {
        stdout.print("\n", .{}) catch {};
    }

    stdout.flush() catch {};
    return 0;
}

fn writeEscaped(writer: *std.Io.Writer, s: []const u8) !void {
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            switch (s[i + 1]) {
                '\\' => {
                    try writer.print("\\", .{});
                    i += 2;
                },
                'a' => {
                    try writer.print("\x07", .{});
                    i += 2;
                },
                'b' => {
                    try writer.print("\x08", .{});
                    i += 2;
                },
                'c' => {
                    // \c stops output (no further output including newline)
                    return;
                },
                'e', 'E' => {
                    try writer.print("\x1b", .{});
                    i += 2;
                },
                'f' => {
                    try writer.print("\x0c", .{});
                    i += 2;
                },
                'n' => {
                    try writer.print("\n", .{});
                    i += 2;
                },
                'r' => {
                    try writer.print("\r", .{});
                    i += 2;
                },
                't' => {
                    try writer.print("\t", .{});
                    i += 2;
                },
                'v' => {
                    try writer.print("\x0b", .{});
                    i += 2;
                },
                '0' => {
                    // Octal: \0nnn (up to 3 octal digits)
                    const octal_start = i + 2;
                    var octal_end = octal_start;
                    while (octal_end < s.len and octal_end < octal_start + 3 and
                        s[octal_end] >= '0' and s[octal_end] <= '7')
                    {
                        octal_end += 1;
                    }
                    if (octal_end > octal_start) {
                        const val = std.fmt.parseInt(u8, s[octal_start..octal_end], 8) catch 0;
                        try writer.print("{c}", .{val});
                    } else {
                        try writer.print("\x00", .{});
                    }
                    i = octal_end;
                },
                'x' => {
                    // Hex: \xHH (1-2 hex digits)
                    const hex_start = i + 2;
                    var hex_end = hex_start;
                    while (hex_end < s.len and hex_end < hex_start + 2 and
                        ((s[hex_end] >= '0' and s[hex_end] <= '9') or
                        (s[hex_end] >= 'a' and s[hex_end] <= 'f') or
                        (s[hex_end] >= 'A' and s[hex_end] <= 'F')))
                    {
                        hex_end += 1;
                    }
                    if (hex_end > hex_start) {
                        const val = std.fmt.parseInt(u8, s[hex_start..hex_end], 16) catch 0;
                        try writer.print("{c}", .{val});
                        i = hex_end;
                    } else {
                        try writer.print("\\x", .{});
                        i += 2;
                    }
                },
                else => {
                    // Unknown escape, output literally
                    try writer.print("\\{c}", .{s[i + 1]});
                    i += 2;
                },
            }
        } else {
            try writer.print("{c}", .{s[i]});
            i += 1;
        }
    }
}
