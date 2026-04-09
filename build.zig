const std = @import("std");
const zon = @import("build.zig.zon");
const version = zon.version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options module — exposes `version` to source code via @import("build_options")
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const mod = b.addModule("perpet", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addOptions("build_options", options);

    const actus = b.dependency("actus", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("actus", actus.module("actus"));

    const exe = b.addExecutable(.{
        .name = "perpet",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "perpet", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
