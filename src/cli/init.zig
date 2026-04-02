const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const url = args.next();

    const source_dir = try core.paths.getSourceDir(allocator);
    defer allocator.free(source_dir);

    // Check if source dir already exists
    if (core.fs_ops.fileExists(source_dir)) {
        cli.printErr("perpet: source directory already exists: {s}\n", .{source_dir});
        cli.printErr("Remove it first or use 'perpet update' to sync.\n", .{});
        std.process.exit(1);
    }

    if (url) |remote_url| {
        // Clone from remote
        cli.printOut("Cloning from {s}...\n", .{remote_url});
        var result = try core.git_ops.gitClone(allocator, remote_url, source_dir);
        defer result.deinit(allocator);
        if (!result.success) {
            cli.printErr("perpet: git clone failed:\n{s}", .{result.stderr});
            std.process.exit(1);
        }
        cli.printOut("Cloned to {s}\n", .{source_dir});
    } else {
        // Create new source directory
        try std.fs.makeDirAbsolute(source_dir);

        const home_dir = try core.paths.getHomeMirrorDir(allocator);
        defer allocator.free(home_dir);
        try std.fs.makeDirAbsolute(home_dir);

        // Generate default perpet.toml
        var cfg = try core.config.defaults(allocator);
        defer cfg.deinit();
        const toml_content = try core.config.serialize(allocator, &cfg);
        defer allocator.free(toml_content);

        const config_path = try core.paths.getConfigPath(allocator);
        defer allocator.free(config_path);
        try core.fs_ops.writeContent(allocator, config_path, toml_content);

        // git init
        var result = try core.git_ops.gitInit(allocator, source_dir);
        defer result.deinit(allocator);
        if (!result.success) {
            cli.printErr("perpet: git init failed:\n{s}", .{result.stderr});
        }

        cli.printOut("Initialized perpet at {s}\n", .{source_dir});
        cli.printOut("Edit {s} to configure variables.\n", .{config_path});
    }
}
