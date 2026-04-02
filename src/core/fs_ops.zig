const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const paths = @import("paths.zig");

pub const SyncMode = enum { symlink, copy };

/// Create parent directories for a target path if they don't exist.
pub fn ensureParentDirs(allocator: Allocator, target_path: []const u8) !void {
    const parent = std.fs.path.dirname(target_path) orelse return;
    // Use cwd-relative approach via absolute path
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            // Try creating all ancestors
            try makeDirsRecursive(allocator, parent);
        },
    };
}

fn makeDirsRecursive(allocator: Allocator, path: []const u8) !void {
    var components: std.ArrayList([]const u8) = .empty;
    defer components.deinit(allocator);

    var current: []const u8 = path;
    while (true) {
        std.fs.makeDirAbsolute(current) catch |err| switch (err) {
            error.PathAlreadyExists => break,
            else => {
                const parent = std.fs.path.dirname(current) orelse break;
                try components.append(allocator, current);
                current = parent;
                continue;
            },
        };
        break;
    }

    // Create dirs in reverse order (parent first)
    var i = components.items.len;
    while (i > 0) {
        i -= 1;
        std.fs.makeDirAbsolute(components.items[i]) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
}

/// Create a symlink from target_path pointing to source_path.
/// Removes existing symlink if present.
pub fn createSymlink(source_path: []const u8, target_path: []const u8, allocator: Allocator) !void {
    try ensureParentDirs(allocator, target_path);

    // Check if target already exists
    if (isSymlink(target_path)) {
        try std.fs.deleteFileAbsolute(target_path);
    } else if (fileExists(target_path)) {
        // Regular file exists — caller should handle this
        return error.PathAlreadyExists;
    }

    try std.fs.symLinkAbsolute(source_path, target_path, .{});
}

/// Copy source file to target path.
pub fn copyFile(source_path: []const u8, target_path: []const u8, allocator: Allocator) !void {
    try ensureParentDirs(allocator, target_path);

    // Remove existing symlink if present
    if (isSymlink(target_path)) {
        try std.fs.deleteFileAbsolute(target_path);
    }

    try std.fs.copyFileAbsolute(source_path, target_path, .{});
}

/// Write content bytes to target path (for rendered templates).
pub fn writeContent(allocator: Allocator, target_path: []const u8, content: []const u8) !void {
    try ensureParentDirs(allocator, target_path);

    // Remove existing symlink if present
    if (isSymlink(target_path)) {
        try std.fs.deleteFileAbsolute(target_path);
    }

    const file = try std.fs.createFileAbsolute(target_path, .{});
    defer file.close();
    file.writeAll(content) catch |err| return err;
}

/// Check if a file exists at the given absolute path.
pub fn fileExists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

/// Check if a path is a symlink by attempting to read it as one.
pub fn isSymlink(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    _ = std.fs.readLinkAbsolute(path, &buf) catch return false;
    return true;
}

/// Read the target of a symlink.
pub fn readLink(allocator: Allocator, path: []const u8) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = try std.fs.readLinkAbsolute(path, &buf);
    return allocator.dupe(u8, target);
}

/// Read file content into a string.
pub fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 10 * 1024 * 1024);
}

/// Compare two files byte-by-byte.
pub fn filesEqual(allocator: Allocator, path_a: []const u8, path_b: []const u8) !bool {
    const a = readFile(allocator, path_a) catch return false;
    defer allocator.free(a);
    const b = readFile(allocator, path_b) catch return false;
    defer allocator.free(b);
    return std.mem.eql(u8, a, b);
}

/// Compare file content with a byte buffer.
pub fn fileEqualsContent(allocator: Allocator, path: []const u8, content: []const u8) !bool {
    const data = readFile(allocator, path) catch return false;
    defer allocator.free(data);
    return std.mem.eql(u8, data, content);
}

/// Sync status of a managed file.
pub const FileStatus = enum {
    ok,
    modified,
    missing,
    unlinked,
};

/// Check the sync status of a managed file.
pub fn checkStatus(allocator: Allocator, source_path: []const u8, target_path: []const u8, mode: SyncMode, rendered_content: ?[]const u8) !FileStatus {
    if (!fileExists(target_path)) return .missing;

    if (mode == .symlink) {
        if (!isSymlink(target_path)) return .modified;
        const link_target = readLink(allocator, target_path) catch return .unlinked;
        defer allocator.free(link_target);
        if (!std.mem.eql(u8, link_target, source_path)) return .modified;
        return .ok;
    }

    // Copy mode: compare content
    if (rendered_content) |content| {
        if (try fileEqualsContent(allocator, target_path, content)) return .ok;
        return .modified;
    }

    if (try filesEqual(allocator, source_path, target_path)) return .ok;
    return .modified;
}

// === Tests ===

test "fileExists returns false for nonexistent" {
    try std.testing.expect(!fileExists("/tmp/__perpet_nonexistent_test_file__"));
}

test "isSymlink returns false for nonexistent" {
    try std.testing.expect(!isSymlink("/tmp/__perpet_nonexistent_test_file__"));
}
