const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    _ = args;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("perpet list: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const files = core.manifest.enumerate(allocator, &cfg) catch |err| {
        cli.printErr("perpet list: failed to enumerate files: {}\n", .{err});
        std.process.exit(1);
    };
    defer core.manifest.freeFiles(allocator, files);

    if (files.len == 0) {
        cli.printOut("No managed files.\n", .{});
        return;
    }

    for (files) |file| {
        const mode_str = switch (file.mode) {
            .symlink => "symlink",
            .copy => "copy   ",
        };
        const tmpl_str = if (file.is_template) " (template)" else "";
        cli.printOut("  {s}  {s}{s}\n", .{ mode_str, file.target_rel, tmpl_str });
    }

    cli.printOut("\n{d} file(s) managed.\n", .{files.len});
}
