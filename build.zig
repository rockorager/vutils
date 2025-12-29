const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // uucode Unicode library - only include fields we need
    const uucode_dep = b.lazyDependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{
            "general_category",
        }),
    });

    // Platform module
    const platform_module = b.createModule(.{
        .root_source_file = b.path(switch (target.result.os.tag) {
            .macos => "src/platform/macos.zig",
            .linux => "src/platform/linux.zig",
            else => "src/platform/macos.zig", // fallback for build
        }),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Locale module (with uucode for Unicode character classification)
    const locale_module = b.createModule(.{
        .root_source_file = b.path("src/core/locale.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (uucode_dep) |dep| {
        locale_module.addImport("uucode", dep.module("uucode"));
    }

    // Core module (uses locale)
    const core_module = b.createModule(.{
        .root_source_file = b.path("src/core/count.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_module.addImport("locale", locale_module);
    platform_module.addImport("count", core_module);

    // Main multicall binary (imports wc directly)
    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Wire up the import chain: main -> wc -> platform -> count
    main_module.addImport("platform", platform_module);

    const vutils = b.addExecutable(.{
        .name = "vutils",
        .root_module = main_module,
    });
    b.installArtifact(vutils);

    // Create symlinks for multicall (after install)
    const symlink_step = b.step("symlinks", "Create multicall symlinks");
    const symlinks = [_][]const u8{ "vwc", "wc" };
    for (symlinks) |name| {
        const ln_cmd = b.addSystemCommand(&.{ "ln", "-sf", "vutils", b.fmt("zig-out/bin/{s}", .{name}) });
        ln_cmd.step.dependOn(&vutils.step);
        symlink_step.dependOn(&ln_cmd.step);
    }
    b.getInstallStep().dependOn(symlink_step);

    // Run
    const run_cmd = b.addRunArtifact(vutils);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run vutils");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run unit tests");
    const locale_tests = b.addTest(.{
        .root_module = locale_module,
    });
    test_step.dependOn(&b.addRunArtifact(locale_tests).step);
    const core_tests = b.addTest(.{
        .root_module = core_module,
    });
    test_step.dependOn(&b.addRunArtifact(core_tests).step);

    // Integration tests (require binary to be built first)
    const integration_step = b.step("integration", "Run integration tests");
    integration_step.dependOn(b.getInstallStep());
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/wc_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(integration_tests).step);
}
