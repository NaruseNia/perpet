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

    const raw_path = path orelse {
        cli.printErr("error: missing file path\n", .{});
        cli.printErr("usage: perpet add <path> [--template]\n", .{});
        std.process.exit(1);
    };

    const home_dir = try core.paths.getHomeDir(allocator);
    defer allocator.free(home_dir);

    const abs_path = try resolveToAbsolute(allocator, raw_path, home_dir);
    defer allocator.free(abs_path);

    const rel_path = toHomeRelative(abs_path, home_dir) orelse {
        cli.printErr("error: path is outside $HOME: {s}\n", .{abs_path});
        cli.printErr("  hint: perpet can only manage files under your home directory\n", .{});
        std.process.exit(1);
    };

    if (!core.fs_ops.fileExists(abs_path)) {
        cli.printErr("error: no such file or directory: {s}\n", .{abs_path});
        std.process.exit(1);
    }

    var added_count: usize = 0;

    if (core.fs_ops.isDirectory(abs_path)) {
        cli.printOut("Adding files from {s}/\n", .{rel_path});
        added_count = try addDirectory(allocator, home_dir, rel_path, as_template);
    } else {
        try addSingleFile(allocator, home_dir, rel_path, as_template);
        added_count = 1;
    }

    if (added_count == 0) {
        cli.printOut("No files found in {s}/\n", .{rel_path});
        return;
    }

    cli.printOut("\nAdded {d} file{s}.\n", .{ added_count, if (added_count != 1) "s" else "" });
    cli.printOut("Run 'perpet apply' to deploy.\n", .{});

    // Auto-commit if configured
    var cfg = core.config.load(allocator) catch return;
    defer cfg.deinit();

    if (cfg.git_auto_commit) {
        const source_dir = try core.paths.getSourceDir(allocator);
        defer allocator.free(source_dir);

        var add_result = try core.git_ops.exec(allocator, source_dir, &.{ "add", "-A" });
        defer add_result.deinit(allocator);

        if (add_result.success) {
            const msg = try std.fmt.allocPrint(allocator, "Add {s}", .{rel_path});
            defer allocator.free(msg);
            var commit_result = try core.git_ops.gitCommit(allocator, source_dir, msg);
            defer commit_result.deinit(allocator);
            if (commit_result.success) {
                cli.printOut("Committed to git.\n", .{});
            }
        }
    }
}

fn resolveToAbsolute(allocator: std.mem.Allocator, input: []const u8, home_dir: []const u8) ![]const u8 {
    if (input.len >= 2 and input[0] == '~' and input[1] == '/') {
        return std.fs.path.join(allocator, &.{ home_dir, input[2..] });
    }
    if (std.fs.path.isAbsolute(input)) {
        return allocator.dupe(u8, input);
    }
    return std.fs.path.join(allocator, &.{ home_dir, input });
}

fn toHomeRelative(abs_path: []const u8, home_dir: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, abs_path, home_dir)) {
        var rest = abs_path[home_dir.len..];
        if (rest.len > 0 and rest[0] == '/') rest = rest[1..];
        if (rest.len == 0) return null;
        return rest;
    }
    return null;
}

fn addDirectory(allocator: std.mem.Allocator, home_dir: []const u8, rel_path: []const u8, as_template: bool) !usize {
    const abs_dir = try std.fs.path.join(allocator, &.{ home_dir, rel_path });
    defer allocator.free(abs_dir);

    var dir = std.fs.openDirAbsolute(abs_dir, .{ .iterate = true }) catch |err| {
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

        // Skip .git directory contents
        if (std.mem.startsWith(u8, entry.path, ".git/") or std.mem.eql(u8, entry.path, ".git")) continue;

        const file_rel = std.fs.path.join(allocator, &.{ rel_path, entry.path }) catch continue;
        defer allocator.free(file_rel);

        addSingleFile(allocator, home_dir, file_rel, as_template) catch |err| {
            cli.printErr("  ! {s}: {}\n", .{ file_rel, err });
            continue;
        };
        count += 1;
    }

    return count;
}

fn addSingleFile(allocator: std.mem.Allocator, home_dir: []const u8, rel_path: []const u8, as_template: bool) !void {
    const source_file = try std.fs.path.join(allocator, &.{ home_dir, rel_path });
    defer allocator.free(source_file);

    const mirror_name = if (as_template)
        try std.fmt.allocPrint(allocator, "{s}.tmpl", .{rel_path})
    else
        try allocator.dupe(u8, rel_path);
    defer allocator.free(mirror_name);

    const mirror_path = try core.paths.resolveSourcePath(allocator, mirror_name);
    defer allocator.free(mirror_path);

    try core.fs_ops.ensureParentDirs(allocator, mirror_path);
    try std.fs.copyFileAbsolute(source_file, mirror_path, .{});

    if (as_template) {
        cli.printOut("  + {s} (template)\n", .{rel_path});
    } else {
        cli.printOut("  + {s}\n", .{rel_path});
    }
}
