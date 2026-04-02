const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Returns the user's home directory path.
/// Unix: $HOME, Windows: %USERPROFILE% (fallback: %HOMEDRIVE%%HOMEPATH%)
pub fn getHomeDir(allocator: Allocator) ![]const u8 {
    if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "USERPROFILE")) |val| {
            return val;
        } else |_| {
            const drive = std.process.getEnvVarOwned(allocator, "HOMEDRIVE") catch return error.HomeDirNotFound;
            defer allocator.free(drive);
            const path = std.process.getEnvVarOwned(allocator, "HOMEPATH") catch return error.HomeDirNotFound;
            defer allocator.free(path);
            return std.fs.path.join(allocator, &.{ drive, path });
        }
    } else {
        return std.process.getEnvVarOwned(allocator, "HOME") catch return error.HomeDirNotFound;
    }
}

/// Returns the perpet source directory path.
/// Uses $PERPET_SOURCE_DIR if set, otherwise ~/.perpet/
pub fn getSourceDir(allocator: Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "PERPET_SOURCE_DIR")) |val| {
        return val;
    } else |_| {
        const home = try getHomeDir(allocator);
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, ".perpet" });
    }
}

/// Returns the path to perpet.toml within the source directory.
pub fn getConfigPath(allocator: Allocator) ![]const u8 {
    const source = try getSourceDir(allocator);
    defer allocator.free(source);
    return std.fs.path.join(allocator, &.{ source, "perpet.toml" });
}

/// Returns the path to the home/ subdirectory within the source directory.
pub fn getHomeMirrorDir(allocator: Allocator) ![]const u8 {
    const source = try getSourceDir(allocator);
    defer allocator.free(source);
    return std.fs.path.join(allocator, &.{ source, "home" });
}

/// Resolves a relative path under home/ to its absolute target path under $HOME.
/// Strips the .tmpl suffix if present.
pub fn resolveTargetPath(allocator: Allocator, rel_path: []const u8) ![]const u8 {
    const home = try getHomeDir(allocator);
    defer allocator.free(home);
    const clean = stripTmplSuffix(rel_path);
    return std.fs.path.join(allocator, &.{ home, clean });
}

/// Resolves a relative path to its absolute source path under the home/ mirror directory.
pub fn resolveSourcePath(allocator: Allocator, rel_path: []const u8) ![]const u8 {
    const mirror = try getHomeMirrorDir(allocator);
    defer allocator.free(mirror);
    return std.fs.path.join(allocator, &.{ mirror, rel_path });
}

/// Strips the .tmpl suffix from a path if present.
pub fn stripTmplSuffix(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".tmpl")) {
        return path[0 .. path.len - 5];
    }
    return path;
}

/// Returns true if the path has a .tmpl suffix.
pub fn hasTmplSuffix(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".tmpl");
}

/// Returns the detected OS name as a string for template variables.
pub fn getOsName() []const u8 {
    return switch (builtin.os.tag) {
        .macos => "macos",
        .linux => "linux",
        .windows => "windows",
        else => "unknown",
    };
}

/// Returns the detected architecture as a string for template variables.
pub fn getArchName() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => "unknown",
    };
}

test "stripTmplSuffix" {
    try std.testing.expectEqualStrings(".gitconfig", stripTmplSuffix(".gitconfig.tmpl"));
    try std.testing.expectEqualStrings(".bashrc", stripTmplSuffix(".bashrc"));
    try std.testing.expectEqualStrings("foo.tmpl.bak", stripTmplSuffix("foo.tmpl.bak"));
}

test "hasTmplSuffix" {
    try std.testing.expect(hasTmplSuffix(".gitconfig.tmpl"));
    try std.testing.expect(!hasTmplSuffix(".bashrc"));
}

test "getOsName returns known value" {
    const os = getOsName();
    try std.testing.expect(os.len > 0);
}
