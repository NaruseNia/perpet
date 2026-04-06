const std = @import("std");
const builtin = @import("builtin");

/// Interactive list selector.
/// On POSIX: uses raw terminal mode with arrow key navigation.
/// On Windows: falls back to number input.
/// Returns the index of the selected item, or null if cancelled.
pub fn selectFromList(items: []const []const u8, title: []const u8) ?usize {
    if (items.len == 0) return null;

    if (comptime builtin.os.tag == .windows) {
        return selectFallback(items, title);
    } else {
        return selectInteractive(items, title);
    }
}

/// Fallback: display numbered list and read a number from stdin.
fn selectFallback(items: []const []const u8, title: []const u8) ?usize {
    const stdout = std.fs.File.stdout();
    const stdin = std.fs.File.stdin();

    stdout.writeAll(title) catch return null;
    stdout.writeAll("\n") catch return null;

    for (items, 0..) |item, i| {
        var buf: [16]u8 = undefined;
        const prefix = std.fmt.bufPrint(&buf, "  {d}) ", .{i + 1}) catch return null;
        stdout.writeAll(prefix) catch return null;
        stdout.writeAll(item) catch return null;
        stdout.writeAll("\n") catch return null;
    }

    stdout.writeAll("Enter number (or q to cancel): ") catch return null;

    var line_buf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < line_buf.len) {
        var byte: [1]u8 = undefined;
        const n = stdin.read(&byte) catch return null;
        if (n == 0) return null;
        if (byte[0] == '\n' or byte[0] == '\r') break;
        line_buf[i] = byte[0];
        i += 1;
    }
    const line = std.mem.trim(u8, line_buf[0..i], " \t\r");
    if (line.len == 0 or (line.len == 1 and (line[0] == 'q' or line[0] == 'Q'))) return null;

    const num = std.fmt.parseInt(usize, line, 10) catch return null;
    if (num < 1 or num > items.len) return null;
    return num - 1;
}

/// Interactive POSIX selector with raw terminal and arrow keys.
fn selectInteractive(items: []const []const u8, title: []const u8) ?usize {
    const posix = std.posix;
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();

    // Save original termios and switch to raw mode
    const original = posix.tcgetattr(stdin.handle) catch return null;
    var raw = original;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    posix.tcsetattr(stdin.handle, .NOW, raw) catch return null;

    defer {
        posix.tcsetattr(stdin.handle, .NOW, original) catch {};
        stdout.writeAll("\x1b[?25h") catch {};
    }

    // Hide cursor
    stdout.writeAll("\x1b[?25l") catch {};

    var cursor: usize = 0;
    var first_draw = true;

    while (true) {
        // Move cursor up to redraw (except on first draw)
        if (!first_draw) {
            var buf: [32]u8 = undefined;
            const move_up = std.fmt.bufPrint(&buf, "\x1b[{d}A\r", .{items.len + 2}) catch break;
            stdout.writeAll(move_up) catch break;
        }
        first_draw = false;

        // Draw title
        stdout.writeAll(title) catch break;
        stdout.writeAll("\n") catch break;

        // Draw items
        for (items, 0..) |item, i| {
            if (i == cursor) {
                stdout.writeAll("  \x1b[7m > ") catch break;
                stdout.writeAll(item) catch break;
                stdout.writeAll(" \x1b[0m\x1b[K\n") catch break;
            } else {
                stdout.writeAll("    ") catch break;
                stdout.writeAll(item) catch break;
                stdout.writeAll("\x1b[K\n") catch break;
            }
        }

        // Hint line
        stdout.writeAll("  \x1b[2m↑/↓: move  Enter: select  q/Esc: cancel\x1b[0m\x1b[K\n") catch break;

        // Read input
        var byte: [1]u8 = undefined;
        const n = stdin.read(&byte) catch break;
        if (n == 0) break;

        switch (byte[0]) {
            '\n', '\r' => {
                return cursor;
            },
            'q', 0x1b => {
                if (byte[0] == 0x1b) {
                    var seq: [2]u8 = undefined;
                    const seq_n = stdin.read(&seq) catch return null;
                    if (seq_n == 0) return null;
                    if (seq_n >= 2 and seq[0] == '[') {
                        switch (seq[1]) {
                            'A' => {
                                if (cursor > 0) cursor -= 1;
                            },
                            'B' => {
                                if (cursor < items.len - 1) cursor += 1;
                            },
                            else => {},
                        }
                    } else if (seq_n == 1 and seq[0] == '[') {
                        var dir: [1]u8 = undefined;
                        const dir_n = stdin.read(&dir) catch continue;
                        if (dir_n > 0) {
                            switch (dir[0]) {
                                'A' => {
                                    if (cursor > 0) cursor -= 1;
                                },
                                'B' => {
                                    if (cursor < items.len - 1) cursor += 1;
                                },
                                else => {},
                            }
                        }
                    }
                } else {
                    return null;
                }
            },
            'k' => {
                if (cursor > 0) cursor -= 1;
            },
            'j' => {
                if (cursor < items.len - 1) cursor += 1;
            },
            else => {},
        }
    }

    return null;
}
