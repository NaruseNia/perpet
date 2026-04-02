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
        cli.printErr("error: missing file path\n", .{});
        cli.printErr("usage: perpet remove <path> [--restore]\n", .{});
        std.process.exit(1);
    };

    const mirror_path = core.paths.resolveSourcePath(allocator, rel_path) catch |err| {
        cli.printErr("error: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(mirror_path);

    const tmpl_name = std.fmt.allocPrint(allocator, "{s}.tmpl", .{rel_path}) catch |err| {
        cli.printErr("error: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(tmpl_name);

    const tmpl_mirror_path = core.paths.resolveSourcePath(allocator, tmpl_name) catch |err| {
        cli.printErr("error: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(tmpl_mirror_path);

    const actual_path = if (core.fs_ops.fileExists(mirror_path))
        mirror_path
    else if (core.fs_ops.fileExists(tmpl_mirror_path))
        tmpl_mirror_path
    else {
        cli.printErr("error: '{s}' is not managed by perpet\n", .{rel_path});
        cli.printErr("  hint: run 'perpet list' to see managed files\n", .{});
        std.process.exit(1);
    };

    if (restore) {
        const target_path = core.paths.resolveTargetPath(allocator, rel_path) catch |err| {
            cli.printErr("error: {}\n", .{err});
            return;
        };
        defer allocator.free(target_path);

        if (core.fs_ops.isSymlink(target_path)) {
            std.fs.deleteFileAbsolute(target_path) catch {};
            cli.printOut("  - {s} (symlink removed from $HOME)\n", .{rel_path});
        }
    }

    std.fs.deleteFileAbsolute(actual_path) catch |err| {
        cli.printErr("error: failed to delete {s}: {}\n", .{ actual_path, err });
        std.process.exit(1);
    };

    cli.printOut("  - {s}\n", .{rel_path});
    cli.printOut("\nRemoved from perpet management.\n", .{});

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
            if (commit_result.success) {
                cli.printOut("Committed to git.\n", .{});
            }
        }
    }
}
