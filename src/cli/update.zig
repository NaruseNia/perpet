const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");
const apply_cmd = @import("apply.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    _ = args;
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

    cli.printOut("Pulling latest changes...\n", .{});
    var result = core.git_ops.gitPull(allocator, source_dir) catch |err| {
        cli.printErr("error: git pull failed: {}\n", .{err});
        std.process.exit(1);
    };
    defer result.deinit(allocator);

    if (!result.success) {
        if (result.stderr.len > 0) {
            cli.printErr("{s}", .{result.stderr});
        }
        cli.printErr("\nerror: git pull failed\n", .{});
        cli.printErr("  hint: resolve conflicts manually, then run 'perpet apply'\n", .{});
        std.process.exit(1);
    }

    if (result.stdout.len > 0) {
        cli.printOut("{s}", .{result.stdout});
    }

    cli.printOut("\nApplying dotfiles...\n", .{});
    var apply_args = try std.process.argsWithAllocator(allocator);
    defer apply_args.deinit();
    _ = apply_args.skip();
    _ = apply_args.skip();
    try apply_cmd.run(&apply_args);
}
