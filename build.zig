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

    // wc binary
    const wc_module = b.createModule(.{
        .root_source_file = b.path("src/wc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (uucode_dep) |dep| {
        wc_module.addImport("uucode", dep.module("uucode"));
    }

    const wc = b.addExecutable(.{
        .name = "wc",
        .root_module = wc_module,
    });
    b.installArtifact(wc);

    // Run
    const run_cmd = b.addRunArtifact(wc);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run wc");
    run_step.dependOn(&run_cmd.step);

    // Core module for tests (with uucode)
    const core_module = b.createModule(.{
        .root_source_file = b.path("src/core/count.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (uucode_dep) |dep| {
        core_module.addImport("uucode", dep.module("uucode"));
    }

    // Tests
    const test_step = b.step("test", "Run unit tests");
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
