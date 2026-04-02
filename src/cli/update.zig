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
        cli.printErr("perpet update: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(source_dir);

    if (!core.fs_ops.fileExists(source_dir)) {
        cli.printErr("perpet update: source directory not found. Run 'perpet init' first.\n", .{});
        std.process.exit(1);
    }

    cli.printOut("Pulling latest changes...\n", .{});
    var result = core.git_ops.gitPull(allocator, source_dir) catch |err| {
        cli.printErr("perpet update: git pull failed: {}\n", .{err});
        std.process.exit(1);
    };
    defer result.deinit(allocator);

    if (!result.success) {
        cli.printErr("perpet update: git pull failed:\n{s}", .{result.stderr});
        cli.printErr("Resolve conflicts manually, then run 'perpet apply'.\n", .{});
        std.process.exit(1);
    }

    if (result.stdout.len > 0) {
        cli.printOut("{s}", .{result.stdout});
    }

    // Apply changes
    cli.printOut("Applying dotfiles...\n", .{});
    var apply_args = std.process.args();
    // Create a dummy args iterator (no args for apply)
    _ = apply_args.skip();
    _ = apply_args.skip();
    try apply_cmd.run(&apply_args);
}
