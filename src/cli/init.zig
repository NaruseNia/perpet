const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

const default_perpetignore =
    \\# perpet ignore patterns
    \\# Files and directories listed here are skipped by 'perpet add <directory>'
    \\#
    \\# Syntax:
    \\#   .DS_Store       exact filename match
    \\#   *.log           glob pattern (wildcard does not cross directories)
    \\#   node_modules/   directory prefix (matches everything inside)
    \\#   **/build        match at any directory depth
    \\
    \\# Version control
    \\.git/
    \\.gitignore
    \\
    \\# OS generated files
    \\.DS_Store
    \\Thumbs.db
    \\
    \\# Editor swap / backup files
    \\*.swp
    \\*~
    \\
;

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var url: ?[]const u8 = null;
    var non_interactive = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--non-interactive") or std.mem.eql(u8, arg, "-y")) {
            non_interactive = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            url = arg;
        }
    }

    const source_dir = try core.paths.getSourceDir(allocator);
    defer allocator.free(source_dir);

    if (core.fs_ops.fileExists(source_dir)) {
        cli.printErr("error: source directory already exists at {s}\n", .{source_dir});
        cli.printErr("  hint: remove it first, or use 'perpet update' to pull latest changes\n", .{});
        std.process.exit(1);
    }

    if (url) |remote_url| {
        try cloneFromRemote(allocator, remote_url, source_dir);
    } else if (non_interactive) {
        try initWithDefaults(allocator, source_dir);
    } else {
        try initInteractive(allocator, source_dir);
    }
}

fn cloneFromRemote(allocator: std.mem.Allocator, remote_url: []const u8, source_dir: []const u8) !void {
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

    // Generate perpet.toml if the cloned repo doesn't have one
    const config_path = try core.paths.getConfigPath(allocator);
    defer allocator.free(config_path);
    if (!core.fs_ops.fileExists(config_path)) {
        var cfg = try core.config.defaults(allocator);
        defer cfg.deinit();
        const toml_content = try core.config.serialize(allocator, &cfg);
        defer allocator.free(toml_content);
        try core.fs_ops.writeContent(allocator, config_path, toml_content);
        cli.printOut("Generated perpet.toml (not found in repository)\n", .{});
    }

    cli.printOut("\nCreated {s}\n", .{source_dir});
    cli.printOut("Run 'perpet apply' to deploy your dotfiles.\n", .{});
}

fn initWithDefaults(allocator: std.mem.Allocator, source_dir: []const u8) !void {
    try createSourceDir(allocator, source_dir);

    var cfg = try core.config.defaults(allocator);
    defer cfg.deinit();

    try writeConfigAndFinish(allocator, &cfg, source_dir);
}

fn initInteractive(allocator: std.mem.Allocator, source_dir: []const u8) !void {
    cli.printOut("Setting up perpet. Press Enter to accept defaults.\n\n", .{});

    // Gather user info
    const name = try cli.prompt(allocator, "Your name", "");
    defer allocator.free(name);
    const email = try cli.prompt(allocator, "Your email", "");
    defer allocator.free(email);

    // Settings
    cli.printOut("\n", .{});
    const mode_input = try cli.prompt(allocator, "Default mode", "symlink");
    defer allocator.free(mode_input);
    const auto_commit = cli.promptYesNo("Auto-commit on add/remove?", false);

    // Build config
    try createSourceDir(allocator, source_dir);

    var cfg = try core.config.defaults(allocator);
    defer cfg.deinit();

    // Apply user inputs
    if (std.mem.eql(u8, mode_input, "copy")) {
        cfg.default_mode = .copy;
    }
    cfg.git_auto_commit = auto_commit;

    if (name.len > 0) {
        try cfg.variables.put(try allocator.dupe(u8, "name"), try allocator.dupe(u8, name));
    }
    if (email.len > 0) {
        try cfg.variables.put(try allocator.dupe(u8, "email"), try allocator.dupe(u8, email));
    }

    try writeConfigAndFinish(allocator, &cfg, source_dir);
}

fn createSourceDir(allocator: std.mem.Allocator, source_dir: []const u8) !void {
    try std.fs.makeDirAbsolute(source_dir);

    const home_dir = try core.paths.getHomeMirrorDir(allocator);
    defer allocator.free(home_dir);
    try std.fs.makeDirAbsolute(home_dir);
}

fn writeConfigAndFinish(allocator: std.mem.Allocator, cfg: *const core.config.Config, source_dir: []const u8) !void {
    const toml_content = try core.config.serialize(allocator, cfg);
    defer allocator.free(toml_content);

    const config_path = try core.paths.getConfigPath(allocator);
    defer allocator.free(config_path);
    try core.fs_ops.writeContent(allocator, config_path, toml_content);

    // Generate default .perpetignore
    const ignore_path = try std.fs.path.join(allocator, &.{ source_dir, ".perpetignore" });
    defer allocator.free(ignore_path);
    try core.fs_ops.writeContent(allocator, ignore_path, default_perpetignore);

    // git init
    var result = try core.git_ops.gitInit(allocator, source_dir);
    defer result.deinit(allocator);
    if (!result.success) {
        cli.printErr("warning: git init failed (git may not be installed)\n", .{});
    }

    cli.printOut("\nInitialized perpet at {s}\n\n", .{source_dir});
    cli.printOut("Next steps:\n", .{});
    cli.printOut("  perpet add <file>     Add dotfiles to management\n", .{});
    cli.printOut("  perpet apply          Deploy symlinks to $HOME\n", .{});
    cli.printOut("  perpet config edit    Edit configuration\n", .{});
}
