const std = @import("std");
const posix = std.posix;

/// Interactive list selector using raw terminal mode.
/// Returns the index of the selected item, or null if cancelled.
pub fn selectFromList(items: []const []const u8, title: []const u8) ?usize {
    if (items.len == 0) return null;

    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();

    // Save original termios and switch to raw mode
    const original = posix.tcgetattr(stdin.handle) catch return null;
    var raw = original;
    // Disable canonical mode and echo
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    posix.tcsetattr(stdin.handle, .NOW, raw) catch return null;

    defer {
        // Restore original terminal settings
        posix.tcsetattr(stdin.handle, .NOW, original) catch {};
        // Show cursor
        stdout.writeAll("\x1b[?25h") catch {};
    }

    // Hide cursor
    stdout.writeAll("\x1b[?25h") catch {};

    var cursor: usize = 0;
    var first_draw = true;

    while (true) {
        // Move cursor up to redraw (except on first draw)
        if (!first_draw) {
            var buf: [32]u8 = undefined;
            // +1 for the title line, +1 for the hint line
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
                // Highlighted: reverse video
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
                // Selected
                stdout.writeAll("\n") catch {};
                return cursor;
            },
            'q', 0x1b => {
                // Check if it's an escape sequence (arrow keys) or just Esc
                if (byte[0] == 0x1b) {
                    // Try to read more (could be arrow key sequence)
                    var seq: [2]u8 = undefined;
                    const seq_n = stdin.read(&seq) catch {
                        // Just Esc key
                        stdout.writeAll("\n") catch {};
                        return null;
                    };
                    if (seq_n == 0) {
                        stdout.writeAll("\n") catch {};
                        return null;
                    }
                    if (seq_n >= 2 and seq[0] == '[') {
                        switch (seq[1]) {
                            'A' => { // Up
                                if (cursor > 0) cursor -= 1;
                            },
                            'B' => { // Down
                                if (cursor < items.len - 1) cursor += 1;
                            },
                            else => {},
                        }
                    } else if (seq_n == 1 and seq[0] == '[') {
                        // Read one more byte for the direction
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
                    // 'q' key
                    stdout.writeAll("\n") catch {};
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
