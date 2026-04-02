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

    // Check if it's a directory in the mirror
    if (core.fs_ops.isDirectory(mirror_path)) {
        const count = try removeDirectory(allocator, mirror_path, rel_path, restore);
        if (count == 0) {
            cli.printErr("error: no managed files found in '{s}'\n", .{rel_path});
            std.process.exit(1);
        }
        cli.printOut("\nRemoved {d} file{s} from perpet management.\n", .{ count, if (count != 1) "s" else "" });
    } else {
        const actual_path = if (core.fs_ops.fileExists(mirror_path))
            mirror_path
        else if (core.fs_ops.fileExists(tmpl_mirror_path))
            tmpl_mirror_path
        else {
            cli.printErr("error: '{s}' is not managed by perpet\n", .{rel_path});
            cli.printErr("  hint: run 'perpet list' to see managed files\n", .{});
            std.process.exit(1);
        };

        try removeSingleFile(allocator, actual_path, rel_path, restore);
        cli.printOut("\nRemoved from perpet management.\n", .{});
    }

    // Clean up empty directories in mirror
    cleanEmptyParents(allocator, mirror_path);

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

fn removeSingleFile(allocator: std.mem.Allocator, actual_path: []const u8, rel_path: []const u8, restore: bool) !void {
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
}

fn removeDirectory(allocator: std.mem.Allocator, mirror_dir: []const u8, rel_path: []const u8, restore: bool) !usize {
    var dir = std.fs.openDirAbsolute(mirror_dir, .{ .iterate = true }) catch |err| {
        cli.printErr("error: cannot open directory {s}: {}\n", .{ rel_path, err });
        std.process.exit(1);
    };
    defer dir.close();

    var walker = dir.walk(allocator) catch |err| {
        cli.printErr("error: cannot read directory {s}: {}\n", .{ rel_path, err });
        std.process.exit(1);
    };
    defer walker.deinit();

    var count: usize = 0;
    while (walker.next() catch null) |entry| {
        if (entry.kind != .file) continue;

        const file_rel = std.fs.path.join(allocator, &.{ rel_path, entry.path }) catch continue;
        defer allocator.free(file_rel);

        const file_mirror = std.fs.path.join(allocator, &.{ mirror_dir, entry.path }) catch continue;
        defer allocator.free(file_mirror);

        removeSingleFile(allocator, file_mirror, file_rel, restore) catch |err| {
            cli.printErr("  ! {s}: {}\n", .{ file_rel, err });
            continue;
        };
        count += 1;
    }

    // Remove the directory tree from mirror
    std.fs.deleteTreeAbsolute(mirror_dir) catch {};

    return count;
}

fn cleanEmptyParents(allocator: std.mem.Allocator, path: []const u8) void {
    const home_mirror = core.paths.getHomeMirrorDir(allocator) catch return;
    defer allocator.free(home_mirror);

    var current = std.fs.path.dirname(path) orelse return;
    while (current.len > home_mirror.len) {
        std.fs.deleteDirAbsolute(current) catch break; // stops if not empty
        current = std.fs.path.dirname(current) orelse break;
    }
}
