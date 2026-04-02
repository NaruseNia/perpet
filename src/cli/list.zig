const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    _ = args;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("error: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const files = core.manifest.enumerate(allocator, &cfg) catch |err| {
        cli.printErr("error: failed to read managed files: {}\n", .{err});
        std.process.exit(1);
    };
    defer core.manifest.freeFiles(allocator, files);

    if (files.len == 0) {
        cli.printOut("No managed files.\n", .{});
        cli.printOut("  hint: run 'perpet add <file>' to start managing dotfiles\n", .{});
        return;
    }

    for (files) |file| {
        const mode_str: []const u8 = switch (file.mode) {
            .symlink => "symlink ",
            .copy => "copy    ",
        };
        if (file.is_template) {
            cli.printOut("  {s} {s} (template)\n", .{ mode_str, file.target_rel });
        } else {
            cli.printOut("  {s} {s}\n", .{ mode_str, file.target_rel });
        }
    }

    cli.printOut("\n{d} file{s} managed.\n", .{ files.len, if (files.len != 1) "s" else "" });
}
