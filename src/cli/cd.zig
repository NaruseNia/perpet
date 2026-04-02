const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    _ = args;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const source_dir = core.paths.getSourceDir(allocator) catch |err| {
        cli.printErr("perpet cd: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(source_dir);

    // Print to stdout for shell integration: cd $(perpet cd)
    const file = std.fs.File.stdout();
    file.writeAll(source_dir) catch {};
    file.writeAll("\n") catch {};
}
