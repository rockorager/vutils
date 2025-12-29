//! vutils cat - POSIX-compliant file concatenation
//! Reads files in sequence and writes to stdout

const std = @import("std");
const builtin = @import("builtin");

const READ_BUF_SIZE = 32 * 1024;
const WRITE_BUF_SIZE = if (builtin.os.tag == .macos) 64 * 1024 else 4096;

const Options = struct {
    unbuffered: bool = false,
};

pub fn run() u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    return main(allocator) catch |err| {
        var buf: [WRITE_BUF_SIZE]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buf);
        stderr_writer.interface.print("cat: {s}\n", .{@errorName(err)}) catch {};
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
                    'u' => opts.unbuffered = true,
                    else => {
                        stderr.print("cat: invalid option -- '{c}'\n", .{ch}) catch {};
                        stderr.print("Usage: cat [-u] [file ...]\n", .{}) catch {};
                        stderr.flush() catch {};
                        return 1;
                    },
                }
            }
        } else {
            try paths.append(allocator, arg);
        }
    }

    const stdout_file = std.fs.File.stdout();

    if (paths.items.len == 0) {
        catStdin(stdout_file, opts.unbuffered) catch |err| {
            printError(stderr, "-", err);
            had_error = true;
        };
    } else {
        var stdin_read = false;
        for (paths.items) |path| {
            if (std.mem.eql(u8, path, "-")) {
                if (stdin_read) continue;
                catStdin(stdout_file, opts.unbuffered) catch |err| {
                    printError(stderr, "-", err);
                    had_error = true;
                };
                stdin_read = true;
            } else {
                catFile(path, stdout_file, opts.unbuffered) catch |err| {
                    printError(stderr, path, err);
                    had_error = true;
                };
            }
        }
    }

    stderr.flush() catch {};
    return if (had_error) 1 else 0;
}

fn catFile(path: []const u8, stdout: std.fs.File, unbuffered: bool) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    try copyToStdout(file, stdout, unbuffered);
}

fn catStdin(stdout: std.fs.File, unbuffered: bool) !void {
    const stdin = std.fs.File.stdin();
    try copyToStdout(stdin, stdout, unbuffered);
}

fn copyToStdout(input: std.fs.File, stdout: std.fs.File, unbuffered: bool) !void {
    var read_buf: [READ_BUF_SIZE]u8 = undefined;

    if (unbuffered) {
        while (true) {
            const n = try input.read(&read_buf);
            if (n == 0) break;
            try stdout.writeAll(read_buf[0..n]);
        }
    } else {
        var write_buf: [WRITE_BUF_SIZE]u8 = undefined;
        var stdout_writer = stdout.writer(&write_buf);

        while (true) {
            const n = try input.read(&read_buf);
            if (n == 0) break;
            _ = try stdout_writer.interface.write(read_buf[0..n]);
        }
        try stdout_writer.interface.flush();
    }
}

fn printError(writer: *std.Io.Writer, path: []const u8, err: anyerror) void {
    const msg = switch (err) {
        error.FileNotFound => "No such file or directory",
        error.AccessDenied => "Permission denied",
        error.IsDir => "Is a directory",
        error.NameTooLong => "File name too long",
        else => "I/O error",
    };
    writer.print("cat: {s}: {s}\n", .{ path, msg }) catch {};
}
