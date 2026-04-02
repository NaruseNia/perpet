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

    if (core.fs_ops.fileExists(source_dir)) {
        cli.printErr("error: source directory already exists at {s}\n", .{source_dir});
        cli.printErr("  hint: remove it first, or use 'perpet update' to pull latest changes\n", .{});
        std.process.exit(1);
    }

    if (url) |remote_url| {
        cli.printOut("Cloning {s} ...\n", .{remote_url});
        var result = try core.git_ops.gitClone(allocator, remote_url, source_dir);
        defer result.deinit(allocator);
        if (!result.success) {
            cli.printErr("error: git clone failed\n", .{});
            if (result.stderr.len > 0) {
                cli.printErr("{s}", .{result.stderr});
            }
            std.process.exit(1);
        }
        cli.printOut("\n  Created {s}\n", .{source_dir});
        cli.printOut("\n  Run 'perpet apply' to deploy your dotfiles.\n", .{});
    } else {
        try std.fs.makeDirAbsolute(source_dir);

        const home_dir = try core.paths.getHomeMirrorDir(allocator);
        defer allocator.free(home_dir);
        try std.fs.makeDirAbsolute(home_dir);

        var cfg = try core.config.defaults(allocator);
        defer cfg.deinit();
        const toml_content = try core.config.serialize(allocator, &cfg);
        defer allocator.free(toml_content);

        const config_path = try core.paths.getConfigPath(allocator);
        defer allocator.free(config_path);
        try core.fs_ops.writeContent(allocator, config_path, toml_content);

        var result = try core.git_ops.gitInit(allocator, source_dir);
        defer result.deinit(allocator);
        if (!result.success) {
            cli.printErr("warning: git init failed (git may not be installed)\n", .{});
        }

        cli.printOut("\n  Initialized perpet at {s}\n", .{source_dir});
        cli.printOut("\n  Next steps:\n", .{});
        cli.printOut("    1. Edit {s} to set your variables\n", .{config_path});
        cli.printOut("    2. Run 'perpet add <file>' to start managing dotfiles\n", .{});
        cli.printOut("    3. Run 'perpet apply' to create symlinks\n", .{});
    }
}
