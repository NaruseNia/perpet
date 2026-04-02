const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const source_dir = core.paths.getSourceDir(allocator) catch |err| {
        cli.printErr("error: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(source_dir);

    if (!core.fs_ops.fileExists(source_dir)) {
        cli.printErr("error: perpet is not initialized\n", .{});
        cli.printErr("  hint: run 'perpet init' first\n", .{});
        std.process.exit(1);
    }

    var git_args: std.ArrayList([]const u8) = .empty;
    defer git_args.deinit(allocator);

    while (args.next()) |arg| {
        try git_args.append(allocator, arg);
    }

    if (git_args.items.len == 0) {
        cli.printErr("error: missing git arguments\n", .{});
        cli.printErr("usage: perpet git <args...>\n", .{});
        cli.printErr("  example: perpet git status\n", .{});
        std.process.exit(1);
    }

    const exit_code = core.git_ops.passthrough(allocator, source_dir, git_args.items) catch |err| {
        cli.printErr("error: failed to run git: {}\n", .{err});
        std.process.exit(1);
    };

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}
