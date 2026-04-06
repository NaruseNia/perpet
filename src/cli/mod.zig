const std = @import("std");
const Allocator = std.mem.Allocator;
const build_options = @import("build_options");

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
pub const config_cmd = @import("config.zig");

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
    config,
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
        .{ "config", .config },
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
    \\  edit [path]       Open a source file in your editor (interactive if no path)
    \\  list              List all managed files
    \\  update            Pull from remote and apply
    \\  config [sub]      Show, edit, or generate perpet.toml
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
    file.writeAll("perpet " ++ build_options.version ++ "\n") catch {};
}

/// Write to stderr for error messages.
pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

/// Write to stdout.
pub fn printOut(comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const output = std.fmt.bufPrint(&buf, fmt, args) catch return;
    std.fs.File.stdout().writeAll(output) catch {};
}

/// Prompt the user for input. Shows `label (default): ` and returns the input,
/// or the default if the user just presses Enter.
pub fn prompt(allocator: std.mem.Allocator, label: []const u8, default: []const u8) ![]const u8 {
    if (default.len > 0) {
        printOut("  {s} ({s}): ", .{ label, default });
    } else {
        printOut("  {s}: ", .{label});
    }

    return readLine(allocator, default);
}

/// Prompt the user with a yes/no question. Returns true for yes.
pub fn promptYesNo(label: []const u8, default: bool) bool {
    const hint = if (default) "Y/n" else "y/N";
    printOut("  {s} ({s}): ", .{ label, hint });

    var buf: [1024]u8 = undefined;
    const line = readLineRaw(&buf) orelse return default;
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0) return default;
    return trimmed[0] == 'y' or trimmed[0] == 'Y';
}

fn readLine(allocator: std.mem.Allocator, default: []const u8) ![]const u8 {
    var buf: [1024]u8 = undefined;
    const line = readLineRaw(&buf) orelse return allocator.dupe(u8, default);
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0) return allocator.dupe(u8, default);
    return allocator.dupe(u8, trimmed);
}

/// Read one line from stdin (up to '\n'), byte by byte.
fn readLineRaw(buf: []u8) ?[]const u8 {
    const stdin = std.fs.File.stdin();
    var i: usize = 0;
    while (i < buf.len) {
        var byte: [1]u8 = undefined;
        const n = stdin.read(&byte) catch return null;
        if (n == 0) {
            // EOF
            return if (i > 0) buf[0..i] else null;
        }
        if (byte[0] == '\n') {
            return buf[0..i];
        }
        buf[i] = byte[0];
        i += 1;
    }
    return buf[0..i];
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
    try std.testing.expectEqual(Command.config, parseCommand("config").?);
    try std.testing.expect(parseCommand("nonexistent") == null);
}
