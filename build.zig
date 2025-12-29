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

    // Locale module (uses bitmap for fast whitespace classification)
    const locale_module = b.createModule(.{
        .root_source_file = b.path("src/core/locale.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Core module (uses locale and uucode for UTF-8 decoding)
    const core_module = b.createModule(.{
        .root_source_file = b.path("src/core/count.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_module.addImport("locale", locale_module);
    if (uucode_dep) |dep| {
        core_module.addImport("uucode", dep.module("uucode"));
    }
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

    // Benchmark: whitespace_table vs uucode
    const bench_step = b.step("bench", "Run whitespace classification benchmark");

    // Create optimized versions of modules for benchmarking
    const bench_locale_module = b.createModule(.{
        .root_source_file = b.path("src/core/locale.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const bench_core_module = b.createModule(.{
        .root_source_file = b.path("src/core/count.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_core_module.addImport("locale", bench_locale_module);
    if (uucode_dep) |dep| {
        bench_core_module.addImport("uucode", dep.module("uucode"));
    }

    const bench_module = b.createModule(.{
        .root_source_file = b.path("bench/whitespace_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_module.addImport("count", bench_core_module);
    bench_module.addImport("locale", bench_locale_module);

    const bench_exe = b.addExecutable(.{
        .name = "whitespace_bench",
        .root_module = bench_module,
    });
    const run_bench = b.addRunArtifact(bench_exe);
    bench_step.dependOn(&run_bench.step);

}
