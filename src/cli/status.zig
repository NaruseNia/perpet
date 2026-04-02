const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    _ = args;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("perpet status: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const files = core.manifest.enumerate(allocator, &cfg) catch |err| {
        cli.printErr("perpet status: failed to enumerate files: {}\n", .{err});
        std.process.exit(1);
    };
    defer core.manifest.freeFiles(allocator, files);

    if (files.len == 0) {
        cli.printOut("No managed files.\n", .{});
        return;
    }

    for (files) |file| {
        const source_path = core.paths.resolveSourcePath(allocator, file.source_rel) catch continue;
        defer allocator.free(source_path);
        const target_path = core.paths.resolveTargetPath(allocator, file.source_rel) catch continue;
        defer allocator.free(target_path);

        const mode: core.fs_ops.SyncMode = switch (file.mode) {
            .symlink => .symlink,
            .copy => .copy,
        };

        // For templates, render content for comparison
        var rendered: ?[]const u8 = null;
        defer if (rendered) |r| allocator.free(r);

        if (file.is_template) {
            if (core.fs_ops.readFile(allocator, source_path)) |content| {
                defer allocator.free(content);
                rendered = core.template.render(allocator, content, cfg.variables) catch null;
            } else |_| {}
        }

        const status = core.fs_ops.checkStatus(allocator, source_path, target_path, mode, rendered) catch .missing;

        const status_str = switch (status) {
            .ok => "  ok",
            .modified => "  modified",
            .missing => "  missing",
            .unlinked => "  unlinked",
        };

        cli.printOut("{s}  {s}\n", .{ status_str, file.target_rel });
    }
}
