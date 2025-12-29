//! vutils - fast, platform-optimized coreutils
//! Multicall binary: dispatch based on argv[0]

const std = @import("std");
const wc = @import("wc.zig");
const echo = @import("echo.zig");

const Tool = struct {
    name: []const u8,
    run: *const fn () u8,
};

const tools = [_]Tool{
    .{ .name = "wc", .run = wc.run },
    .{ .name = "vwc", .run = wc.run },
    .{ .name = "echo", .run = echo.run },
    .{ .name = "vecho", .run = echo.run },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 0) {
        return printUsage();
    }

    // Get binary name from argv[0]
    const invoked_as = std.fs.path.basename(args[0]);

    // Direct invocation as "vutils <tool> [args...]"
    if (std.mem.eql(u8, invoked_as, "vutils")) {
        if (args.len < 2) {
            return printUsage();
        }
        const tool_name = args[1];
        if (findTool(tool_name)) |tool| {
            std.process.exit(tool.run());
        }
        std.debug.print("vutils: unknown tool '{s}'\n", .{tool_name});
        return printUsage();
    }

    // Multicall: invoked as symlink (e.g., "vwc")
    if (findTool(invoked_as)) |tool| {
        std.process.exit(tool.run());
    }

    std.debug.print("vutils: unknown tool '{s}'\n", .{invoked_as});
    return printUsage();
}

fn findTool(name: []const u8) ?Tool {
    for (tools) |tool| {
        if (std.mem.eql(u8, tool.name, name)) {
            return tool;
        }
    }
    return null;
}

fn printUsage() void {
    std.debug.print(
        \\usage: vutils <tool> [args...]
        \\       vwc [args...]     (via symlink)
        \\
        \\tools:
        \\  wc    word, line, byte count
        \\  echo  display a line of text
        \\
    , .{});
}
