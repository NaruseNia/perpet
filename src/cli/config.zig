const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const subcmd = args.next();

    if (subcmd) |cmd| {
        if (std.mem.eql(u8, cmd, "edit")) {
            return editConfig(allocator);
        } else if (std.mem.eql(u8, cmd, "path")) {
            return showPath(allocator);
        } else {
            cli.printErr("error: unknown config subcommand '{s}'\n", .{cmd});
            cli.printErr("usage: perpet config [edit|path]\n", .{});
            std.process.exit(1);
        }
    }

    // Default: show current config
    return showConfig(allocator);
}

fn showConfig(allocator: std.mem.Allocator) !void {
    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("error: failed to load config: {}\n", .{err});
        cli.printErr("  hint: run 'perpet init' to create a new configuration\n", .{});
        std.process.exit(1);
    };
    defer cfg.deinit();

    cli.printOut("[settings]\n", .{});
    cli.printOut("  default_mode    = {s}\n", .{if (cfg.default_mode == .copy) "copy" else "symlink"});
    cli.printOut("  editor          = {s}\n", .{if (cfg.editor.len > 0) cfg.editor else "(not set, using $EDITOR)"});
    cli.printOut("  git_auto_commit = {s}\n", .{if (cfg.git_auto_commit) "true" else "false"});
    cli.printOut("  git_remote      = {s}\n", .{cfg.git_remote});

    cli.printOut("\n[variables]\n", .{});
    var vit = cfg.variables.iterator();
    while (vit.next()) |entry| {
        cli.printOut("  {s} = {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    if (cfg.files.len > 0) {
        cli.printOut("\n[[files]] ({d} override{s})\n", .{ cfg.files.len, if (cfg.files.len != 1) "s" else "" });
        for (cfg.files) |f| {
            if (f.mode) |m| {
                cli.printOut("  {s} -> {s}\n", .{ f.path, if (m == .copy) "copy" else "symlink" });
            }
        }
    }

    cli.printOut("\n  hint: run 'perpet config edit' to modify\n", .{});
}

fn editConfig(allocator: std.mem.Allocator) !void {
    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("error: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const editor = if (cfg.editor.len > 0)
        cfg.editor
    else blk: {
        const env_editor = std.process.getEnvVarOwned(allocator, "EDITOR") catch break :blk @as([]const u8, "");
        if (env_editor.len == 0) {
            allocator.free(env_editor);
            break :blk @as([]const u8, "");
        }
        break :blk env_editor;
    };

    if (editor.len == 0) {
        cli.printErr("error: no editor configured\n", .{});
        cli.printErr("\n", .{});
        cli.printErr("  To fix this, do one of the following:\n", .{});
        cli.printErr("    1. Set the $EDITOR environment variable:\n", .{});
        cli.printErr("       export EDITOR=vim   # add to your .bashrc/.zshrc\n", .{});
        cli.printErr("    2. Or set it in perpet.toml:\n", .{});
        cli.printErr("       [settings]\n", .{});
        cli.printErr("       editor = \"vim\"\n", .{});
        std.process.exit(1);
    }

    const config_path = core.paths.getConfigPath(allocator) catch |err| {
        cli.printErr("error: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(config_path);

    var child = std.process.Child.init(&.{ editor, config_path }, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;

    try child.spawn();
    _ = try child.wait();
}

fn showPath(allocator: std.mem.Allocator) !void {
    const config_path = core.paths.getConfigPath(allocator) catch |err| {
        cli.printErr("error: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(config_path);

    const file = std.fs.File.stdout();
    file.writeAll(config_path) catch {};
    file.writeAll("\n") catch {};
}
