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

const READ_BUF_SIZE = 128 * 1024; // 128KB - larger than BSD's MAXBSIZE

/// Count multiple files in parallel using GCD dispatch_apply
pub fn countFilesParallel(
    paths: []const []const u8,
    allocator: std.mem.Allocator,
) !Counts {
    if (paths.len == 0) return .{};
    if (paths.len == 1) return countFile(paths[0]);

    const results = try allocator.alloc(Counts, paths.len);
    defer allocator.free(results);
    @memset(results, .{});

    const queue = c.dispatch_get_global_queue(c.QOS_CLASS_USER_INITIATED, 0);

    const Context = struct {
        paths: []const []const u8,
        results: []Counts,
    };

    var ctx = Context{ .paths = paths, .results = results };

    // dispatch_apply is synchronous, automatically load-balanced
    c.dispatch_apply_f(paths.len, queue, &ctx, struct {
        fn work(context: ?*anyopaque, idx: usize) callconv(.c) void {
            const cx: *Context = @ptrCast(@alignCast(context));
            cx.results[idx] = countFile(cx.paths[idx]);
        }
    }.work);

    // Sum results
    var total = Counts{};
    for (results) |r| {
        total = total.add(r);
    }
    return total;
}

/// Count a single file
pub fn countFile(path: []const u8) Counts {
    // Use null-terminated path for C APIs
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path.len >= path_buf.len) return .{};
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    const fd = c.open(&path_buf, c.O_RDONLY);
    if (fd < 0) return .{};
    defer _ = c.close(fd);

    // F_NOCACHE for large files - bypass buffer cache
    var st: c.struct_stat = undefined;
    if (c.fstat(fd, &st) == 0 and st.st_size > 1024 * 1024) {
        _ = c.fcntl(fd, c.F_NOCACHE, @as(c_int, 1));
    }

    return countFd(fd);
}

fn countFd(fd: c_int) Counts {
    var buf: [READ_BUF_SIZE]u8 = undefined;
    var total = Counts{};
    var in_word = false;

    while (true) {
        const n = c.read(fd, &buf, buf.len);
        if (n <= 0) break;

        // Respect locale: UTF-8 locale uses Unicode whitespace, C locale uses ASCII
        const state = count.countBufferLocale(buf[0..@intCast(n)], in_word);
        total = total.add(state.counts);
        in_word = state.in_word;
    }

    return total;
}

/// Read from stdin
pub fn countStdin() !Counts {
    return countFd(0);
}
