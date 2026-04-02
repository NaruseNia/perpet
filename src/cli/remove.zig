const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var path: ?[]const u8 = null;
    var restore = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--restore") or std.mem.eql(u8, arg, "-r")) {
            restore = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            path = arg;
        }
    }

    const rel_path = path orelse {
        cli.printErr("perpet remove: missing file path\n", .{});
        cli.printErr("Usage: perpet remove <path> [--restore]\n", .{});
        std.process.exit(1);
    };

    // Try both with and without .tmpl suffix
    const mirror_path = core.paths.resolveSourcePath(allocator, rel_path) catch |err| {
        cli.printErr("perpet remove: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(mirror_path);

    const tmpl_name = std.fmt.allocPrint(allocator, "{s}.tmpl", .{rel_path}) catch |err| {
        cli.printErr("perpet remove: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(tmpl_name);

    const tmpl_mirror_path = core.paths.resolveSourcePath(allocator, tmpl_name) catch |err| {
        cli.printErr("perpet remove: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(tmpl_mirror_path);

    const actual_path = if (core.fs_ops.fileExists(mirror_path))
        mirror_path
    else if (core.fs_ops.fileExists(tmpl_mirror_path))
        tmpl_mirror_path
    else {
        cli.printErr("perpet remove: not managed: {s}\n", .{rel_path});
        std.process.exit(1);
    };

    // Restore: remove symlink/copy from $HOME
    if (restore) {
        const target_path = core.paths.resolveTargetPath(allocator, rel_path) catch |err| {
            cli.printErr("perpet remove: {}\n", .{err});
            return;
        };
        defer allocator.free(target_path);

        if (core.fs_ops.isSymlink(target_path)) {
            std.fs.deleteFileAbsolute(target_path) catch {};
            cli.printOut("Removed symlink {s}\n", .{target_path});
        }
    }

    // Delete from mirror
    std.fs.deleteFileAbsolute(actual_path) catch |err| {
        cli.printErr("perpet remove: failed to delete {s}: {}\n", .{ actual_path, err });
        std.process.exit(1);
    };

    cli.printOut("Removed {s}\n", .{rel_path});

    // Auto-commit if configured
    var cfg = core.config.load(allocator) catch return;
    defer cfg.deinit();

    if (cfg.git_auto_commit) {
        const source_dir = core.paths.getSourceDir(allocator) catch return;
        defer allocator.free(source_dir);

        var add_result = core.git_ops.exec(allocator, source_dir, &.{ "add", "-A" }) catch return;
        defer add_result.deinit(allocator);

        if (add_result.success) {
            const msg = std.fmt.allocPrint(allocator, "Remove {s}", .{rel_path}) catch return;
            defer allocator.free(msg);
            var commit_result = core.git_ops.gitCommit(allocator, source_dir, msg) catch return;
            defer commit_result.deinit(allocator);
        }
    }
}
