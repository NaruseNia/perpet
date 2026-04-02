const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var path: ?[]const u8 = null;
    var as_template = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--template") or std.mem.eql(u8, arg, "-t")) {
            as_template = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            path = arg;
        }
    }

    const rel_path = path orelse {
        cli.printErr("perpet add: missing file path\n", .{});
        cli.printErr("Usage: perpet add <path> [--template]\n", .{});
        std.process.exit(1);
    };

    const home_dir = try core.paths.getHomeDir(allocator);
    defer allocator.free(home_dir);
    const source_file = try std.fs.path.join(allocator, &.{ home_dir, rel_path });
    defer allocator.free(source_file);

    // Verify source file exists in $HOME
    if (!core.fs_ops.fileExists(source_file)) {
        cli.printErr("perpet add: file not found: {s}\n", .{source_file});
        std.process.exit(1);
    }

    // Determine target name in home/ mirror
    const mirror_name = if (as_template)
        try std.fmt.allocPrint(allocator, "{s}.tmpl", .{rel_path})
    else
        try allocator.dupe(u8, rel_path);
    defer allocator.free(mirror_name);

    const mirror_path = try core.paths.resolveSourcePath(allocator, mirror_name);
    defer allocator.free(mirror_path);

    // Copy the file to the mirror directory
    try core.fs_ops.ensureParentDirs(allocator, mirror_path);
    try std.fs.copyFileAbsolute(source_file, mirror_path, .{});

    cli.printOut("Added {s}", .{rel_path});
    if (as_template) {
        cli.printOut(" (template)", .{});
    }
    cli.printOut("\n", .{});

    // Auto-commit if configured
    var cfg = core.config.load(allocator) catch return;
    defer cfg.deinit();

    if (cfg.git_auto_commit) {
        const source_dir = try core.paths.getSourceDir(allocator);
        defer allocator.free(source_dir);

        var add_result = try core.git_ops.gitAdd(allocator, source_dir, &.{mirror_name});
        defer add_result.deinit(allocator);

        if (add_result.success) {
            const msg = try std.fmt.allocPrint(allocator, "Add {s}", .{rel_path});
            defer allocator.free(msg);
            var commit_result = try core.git_ops.gitCommit(allocator, source_dir, msg);
            defer commit_result.deinit(allocator);
        }
    }
}
