const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const rel_path = args.next() orelse {
        cli.printErr("error: missing file path\n", .{});
        cli.printErr("usage: perpet edit <path>\n", .{});
        std.process.exit(1);
    };

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

    // Find the source file (try with and without .tmpl)
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

    const tmpl_path = core.paths.resolveSourcePath(allocator, tmpl_name) catch |err| {
        cli.printErr("error: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(tmpl_path);

    const actual_path = if (core.fs_ops.fileExists(mirror_path))
        mirror_path
    else if (core.fs_ops.fileExists(tmpl_path))
        tmpl_path
    else {
        cli.printErr("error: '{s}' is not managed by perpet\n", .{rel_path});
        cli.printErr("  hint: run 'perpet list' to see managed files\n", .{});
        std.process.exit(1);
    };

    var child = std.process.Child.init(&.{ editor, actual_path }, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;

    try child.spawn();
    _ = try child.wait();
}
