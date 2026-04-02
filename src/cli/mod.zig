const std = @import("std");
const Allocator = std.mem.Allocator;

pub const init_cmd = @import("init.zig");
pub const add_cmd = @import("add.zig");
pub const apply_cmd = @import("apply.zig");
pub const remove_cmd = @import("remove.zig");
pub const diff_cmd = @import("diff.zig");
pub const status_cmd = @import("status.zig");
pub const edit_cmd = @import("edit.zig");
pub const list_cmd = @import("list.zig");
pub const update_cmd = @import("update.zig");
pub const cd_cmd = @import("cd.zig");
pub const git_cmd = @import("git.zig");

pub const Command = enum {
    init,
    add,
    apply,
    remove,
    diff,
    status,
    edit,
    list,
    update,
    cd,
    git,
    help,
    version,
};

pub fn parseCommand(arg: []const u8) ?Command {
    const map = std.StaticStringMap(Command).initComptime(.{
        .{ "init", .init },
        .{ "add", .add },
        .{ "apply", .apply },
        .{ "remove", .remove },
        .{ "rm", .remove },
        .{ "diff", .diff },
        .{ "status", .status },
        .{ "st", .status },
        .{ "edit", .edit },
        .{ "list", .list },
        .{ "ls", .list },
        .{ "update", .update },
        .{ "cd", .cd },
        .{ "git", .git },
        .{ "help", .help },
        .{ "--help", .help },
        .{ "-h", .help },
        .{ "version", .version },
        .{ "--version", .version },
        .{ "-v", .version },
    });
    return map.get(arg);
}

const usage_text =
    \\perpet - beginner-friendly dotfiles manager
    \\
    \\Usage: perpet <command> [options]
    \\
    \\Commands:
    \\  init [url]        Initialize dotfiles repository
    \\  add <path>        Add a file to management
    \\  remove <path>     Remove a file from management
    \\  apply             Apply dotfiles to $HOME
    \\  diff [path]       Show differences between source and target
    \\  status            Show sync status of managed files
    \\  edit <path>       Open a source file in your editor
    \\  list              List all managed files
    \\  update            Pull from remote and apply
    \\  cd                Print source directory path
    \\  git <args...>     Run git commands in source repository
    \\
    \\Options:
    \\  -h, --help        Show this help message
    \\  -v, --version     Show version
    \\
    \\Aliases:
    \\  rm = remove, st = status, ls = list
    \\
;

pub fn printUsage() void {
    const file = std.fs.File.stdout();
    file.writeAll(usage_text) catch {};
}

pub fn printVersion() void {
    const file = std.fs.File.stdout();
    file.writeAll("perpet 0.1.0\n") catch {};
}

/// Write to stderr for error messages.
pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

/// Write to stdout.
pub fn printOut(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    var w = std.fs.File.stdout().writer(&buf);
    w.interface.print(fmt, args) catch {};
    w.interface.flush() catch {};
}

test "parseCommand recognizes all commands" {
    try std.testing.expectEqual(Command.init, parseCommand("init").?);
    try std.testing.expectEqual(Command.add, parseCommand("add").?);
    try std.testing.expectEqual(Command.apply, parseCommand("apply").?);
    try std.testing.expectEqual(Command.remove, parseCommand("remove").?);
    try std.testing.expectEqual(Command.remove, parseCommand("rm").?);
    try std.testing.expectEqual(Command.status, parseCommand("st").?);
    try std.testing.expectEqual(Command.list, parseCommand("ls").?);
    try std.testing.expectEqual(Command.help, parseCommand("--help").?);
    try std.testing.expectEqual(Command.version, parseCommand("-v").?);
    try std.testing.expect(parseCommand("nonexistent") == null);
}
