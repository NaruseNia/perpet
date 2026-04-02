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
        cli.printErr("error: failed to load config: {}\n", .{err});
        cli.printErr("  hint: run 'perpet init' to create a new configuration\n", .{});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const files = core.manifest.enumerate(allocator, &cfg) catch |err| {
        cli.printErr("error: failed to read managed files: {}\n", .{err});
        std.process.exit(1);
    };
    defer core.manifest.freeFiles(allocator, files);

    if (files.len == 0) {
        cli.printOut("No managed files found.\n", .{});
        cli.printOut("  hint: run 'perpet add <file>' to start managing dotfiles\n", .{});
        return;
    }

    if (dry_run) {
        cli.printOut("Dry run: the following changes would be made:\n\n", .{});
    } else {
        cli.printOut("Applying {d} file{s}...\n\n", .{ files.len, if (files.len != 1) "s" else "" });
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
            const tmpl_str = if (file.is_template) ", template" else "";
            cli.printOut("  {s} -> {s} ({s}{s})\n", .{ file.target_rel, target_path, mode_str, tmpl_str });
            applied += 1;
            continue;
        }

        // Template rendering
        if (file.is_template) {
            const source_content = core.fs_ops.readFile(allocator, source_path) catch |err| {
                cli.printErr("  ! {s}: cannot read source: {}\n", .{ file.source_rel, err });
                errors += 1;
                continue;
            };
            defer allocator.free(source_content);

            const rendered = core.template.render(allocator, source_content, cfg.variables) catch |err| {
                cli.printErr("  ! {s}: template error: {}\n", .{ file.source_rel, err });
                errors += 1;
                continue;
            };
            defer allocator.free(rendered);

            core.fs_ops.writeContent(allocator, target_path, rendered) catch |err| {
                cli.printErr("  ! {s}: cannot write: {}\n", .{ target_path, err });
                errors += 1;
                continue;
            };

            cli.printOut("  + {s} (template -> copy)\n", .{file.target_rel});
            applied += 1;
            continue;
        }

        // Non-template files: force-remove existing regular files if --force
        if (force and core.fs_ops.fileExists(target_path) and !core.fs_ops.isSymlink(target_path)) {
            std.fs.deleteFileAbsolute(target_path) catch {};
        }

        if (mode == .symlink) {
            core.fs_ops.createSymlink(source_path, target_path, allocator) catch |err| {
                if (err == error.PathAlreadyExists) {
                    cli.printOut("  ~ {s} (exists, use --force to overwrite)\n", .{file.target_rel});
                    skipped += 1;
                } else {
                    cli.printErr("  ! {s}: {}\n", .{ file.target_rel, err });
                    errors += 1;
                }
                continue;
            };
            cli.printOut("  + {s} (symlink)\n", .{file.target_rel});
        } else {
            core.fs_ops.copyFile(source_path, target_path, allocator) catch |err| {
                cli.printErr("  ! {s}: {}\n", .{ file.target_rel, err });
                errors += 1;
                continue;
            };
            cli.printOut("  + {s} (copy)\n", .{file.target_rel});
        }

        applied += 1;
    }

    cli.printOut("\n", .{});
    if (dry_run) {
        cli.printOut("{d} file{s} would be applied.\n", .{ applied, if (applied != 1) "s" else "" });
    } else {
        cli.printOut("Done: {d} applied", .{applied});
        if (skipped > 0) cli.printOut(", {d} skipped", .{skipped});
        if (errors > 0) cli.printOut(", {d} failed", .{errors});
        cli.printOut(".\n", .{});
    }
}
