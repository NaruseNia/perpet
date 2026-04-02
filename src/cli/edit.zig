const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const rel_path = args.next() orelse {
        cli.printErr("perpet edit: missing file path\n", .{});
        cli.printErr("Usage: perpet edit <path>\n", .{});
        std.process.exit(1);
    };

    // Determine editor
    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("perpet edit: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const editor = if (cfg.editor.len > 0)
        cfg.editor
    else
        std.process.getEnvVarOwned(allocator, "EDITOR") catch {
            cli.printErr("perpet edit: $EDITOR not set and no editor configured in perpet.toml\n", .{});
            std.process.exit(1);
        };

    // Find the source file (try with and without .tmpl)
    const mirror_path = core.paths.resolveSourcePath(allocator, rel_path) catch |err| {
        cli.printErr("perpet edit: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(mirror_path);

    const tmpl_name = std.fmt.allocPrint(allocator, "{s}.tmpl", .{rel_path}) catch |err| {
        cli.printErr("perpet edit: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(tmpl_name);

    const tmpl_path = core.paths.resolveSourcePath(allocator, tmpl_name) catch |err| {
        cli.printErr("perpet edit: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(tmpl_path);

    const actual_path = if (core.fs_ops.fileExists(mirror_path))
        mirror_path
    else if (core.fs_ops.fileExists(tmpl_path))
        tmpl_path
    else {
        cli.printErr("perpet edit: not managed: {s}\n", .{rel_path});
        std.process.exit(1);
    };

    // Launch editor
    var child = std.process.Child.init(&.{ editor, actual_path }, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;

    try child.spawn();
    _ = try child.wait();
}
