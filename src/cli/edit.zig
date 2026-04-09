const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");
const actus = @import("actus");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("error: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    // If no argument given, show interactive file selector
    var rel_path_owned = false;
    const rel_path = args.next() orelse blk: {
        rel_path_owned = true;
        const files = core.manifest.enumerate(allocator, &cfg) catch |err| {
            cli.printErr("error: failed to read managed files: {}\n", .{err});
            std.process.exit(1);
        };
        defer core.manifest.freeFiles(allocator, files);

        if (files.len == 0) {
            cli.printErr("No managed files.\n", .{});
            cli.printErr("  hint: run 'perpet add <file>' to start managing dotfiles\n", .{});
            std.process.exit(1);
        }

        // Build display list
        var display_items: std.ArrayList([]const u8) = .empty;
        defer {
            for (display_items.items) |item| allocator.free(item);
            display_items.deinit(allocator);
        }
        for (files) |file| {
            const label = if (file.is_template)
                std.fmt.allocPrint(allocator, "{s} (template)", .{file.target_rel}) catch {
                    std.process.exit(1);
                }
            else
                allocator.dupe(u8, file.target_rel) catch {
                    std.process.exit(1);
                };
            display_items.append(allocator, label) catch std.process.exit(1);
        }

        // Use actus ListView with filtering for interactive file selection
        var list_view = actus.ListView.init(allocator, display_items.items, .{
            .filterable = true,
            .filter_placeholder = "Filter files...",
        });
        defer list_view.deinit();

        var decorated = actus.Decorated(actus.ListView).init(&list_view, .{
            .title = "Select a file to edit:",
        });

        var app = try actus.App.init();
        defer app.deinit();
        try app.run(&decorated);

        if (list_view.isCancelled() or list_view.selectedIndex() == null) {
            std.process.exit(0);
        }

        const selected = list_view.selectedIndex().?;

        // Return the target_rel of the selected file (need to dupe since files will be freed)
        break :blk allocator.dupe(u8, files[selected].target_rel) catch std.process.exit(1);
    };

    defer if (rel_path_owned) allocator.free(rel_path);

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
