const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var dry_run = false;
    var force = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            force = true;
        }
    }

    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("perpet apply: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const files = core.manifest.enumerate(allocator, &cfg) catch |err| {
        cli.printErr("perpet apply: failed to enumerate files: {}\n", .{err});
        std.process.exit(1);
    };
    defer core.manifest.freeFiles(allocator, files);

    if (files.len == 0) {
        cli.printOut("No managed files found. Use 'perpet add' to add dotfiles.\n", .{});
        return;
    }

    var applied: usize = 0;
    var skipped: usize = 0;
    var errors: usize = 0;

    for (files) |file| {
        const source_path = core.paths.resolveSourcePath(allocator, file.source_rel) catch continue;
        defer allocator.free(source_path);
        const target_path = core.paths.resolveTargetPath(allocator, file.source_rel) catch continue;
        defer allocator.free(target_path);

        const mode: core.fs_ops.SyncMode = switch (file.mode) {
            .symlink => .symlink,
            .copy => .copy,
        };

        if (dry_run) {
            const mode_str = if (mode == .symlink) "symlink" else "copy";
            const tmpl_str = if (file.is_template) " (template)" else "";
            cli.printOut("  {s} -> {s} [{s}{s}]\n", .{ file.target_rel, target_path, mode_str, tmpl_str });
            applied += 1;
            continue;
        }

        // Handle template rendering
        if (file.is_template) {
            const source_content = core.fs_ops.readFile(allocator, source_path) catch |err| {
                cli.printErr("  ERROR reading {s}: {}\n", .{ file.source_rel, err });
                errors += 1;
                continue;
            };
            defer allocator.free(source_content);

            const rendered = core.template.render(allocator, source_content, cfg.variables) catch |err| {
                cli.printErr("  ERROR rendering template {s}: {}\n", .{ file.source_rel, err });
                errors += 1;
                continue;
            };
            defer allocator.free(rendered);

            // Templates are always copied (can't symlink rendered content)
            core.fs_ops.writeContent(allocator, target_path, rendered) catch |err| {
                cli.printErr("  ERROR writing {s}: {}\n", .{ target_path, err });
                errors += 1;
                continue;
            };

            cli.printOut("  {s} (template)\n", .{file.target_rel});
            applied += 1;
            continue;
        }

        // Non-template files
        if (mode == .symlink) {
            core.fs_ops.createSymlink(source_path, target_path, allocator) catch |err| {
                if (err == error.PathAlreadyExists and !force) {
                    cli.printErr("  SKIP {s} (file exists, use --force to overwrite)\n", .{file.target_rel});
                    skipped += 1;
                } else {
                    cli.printErr("  ERROR {s}: {}\n", .{ file.target_rel, err });
                    errors += 1;
                }
                continue;
            };
        } else {
            core.fs_ops.copyFile(source_path, target_path, allocator) catch |err| {
                cli.printErr("  ERROR {s}: {}\n", .{ file.target_rel, err });
                errors += 1;
                continue;
            };
        }

        const mode_str = if (mode == .symlink) "symlink" else "copy";
        cli.printOut("  {s} [{s}]\n", .{ file.target_rel, mode_str });
        applied += 1;
    }

    if (dry_run) {
        cli.printOut("\nDry run: {d} files would be applied.\n", .{applied});
    } else {
        cli.printOut("\nApplied {d} files", .{applied});
        if (skipped > 0) cli.printOut(", {d} skipped", .{skipped});
        if (errors > 0) cli.printOut(", {d} errors", .{errors});
        cli.printOut(".\n", .{});
    }
}
