const std = @import("std");
const Allocator = std.mem.Allocator;
const config_mod = @import("config.zig");
const paths = @import("paths.zig");

pub const ManagedFile = struct {
    /// Relative path under home/ (e.g., ".bashrc" or ".gitconfig.tmpl")
    source_rel: []const u8,
    /// Relative path for target (e.g., ".bashrc" or ".gitconfig", .tmpl stripped)
    target_rel: []const u8,
    mode: config_mod.FileMode,
    is_template: bool,
};

/// Walk the home/ mirror directory and build a list of managed files.
/// Merges per-file config overrides from the [[files]] section.
pub fn enumerate(allocator: Allocator, cfg: *const config_mod.Config) ![]ManagedFile {
    const mirror_dir = try paths.getHomeMirrorDir(allocator);
    defer allocator.free(mirror_dir);

    var result: std.ArrayList(ManagedFile) = .empty;
    errdefer {
        for (result.items) |item| {
            allocator.free(item.source_rel);
            if (item.source_rel.ptr != item.target_rel.ptr) {
                allocator.free(item.target_rel);
            }
        }
        result.deinit(allocator);
    }

    var dir = std.fs.openDirAbsolute(mirror_dir, .{ .iterate = true }) catch {
        // home/ directory doesn't exist yet — return empty list
        return result.toOwnedSlice(allocator);
    };
    defer dir.close();

    var walker = dir.walk(allocator) catch {
        return result.toOwnedSlice(allocator);
    };
    defer walker.deinit();

    while (walker.next() catch null) |entry| {
        if (entry.kind != .file) continue;

        const source_rel = try allocator.dupe(u8, entry.path);
        const has_tmpl = paths.hasTmplSuffix(source_rel);
        const target_rel = if (has_tmpl)
            try allocator.dupe(u8, paths.stripTmplSuffix(source_rel))
        else
            source_rel; // shares allocation when no stripping needed

        // Look up per-file override
        const override = findFileOverride(cfg, target_rel);

        const mode = if (override) |o| o.mode orelse cfg.default_mode else cfg.default_mode;
        const is_template = if (override) |o| o.template orelse has_tmpl else has_tmpl;

        try result.append(allocator, .{
            .source_rel = source_rel,
            .target_rel = target_rel,
            .mode = mode,
            .is_template = is_template,
        });
    }

    return result.toOwnedSlice(allocator);
}

fn findFileOverride(cfg: *const config_mod.Config, target_rel: []const u8) ?*const config_mod.FileEntry {
    for (cfg.files) |*f| {
        if (std.mem.eql(u8, f.path, target_rel)) return f;
    }
    return null;
}

/// Free a slice of ManagedFile returned by enumerate.
pub fn freeFiles(allocator: Allocator, files: []ManagedFile) void {
    for (files) |item| {
        if (item.source_rel.ptr != item.target_rel.ptr) {
            allocator.free(item.target_rel);
        }
        allocator.free(item.source_rel);
    }
    allocator.free(files);
}

// === Tests ===

test "findFileOverride returns null when no match" {
    var cfg = try config_mod.defaults(std.testing.allocator);
    defer cfg.deinit();

    try std.testing.expect(findFileOverride(&cfg, ".bashrc") == null);
}

test "ManagedFile struct layout" {
    const f = ManagedFile{
        .source_rel = ".gitconfig.tmpl",
        .target_rel = ".gitconfig",
        .mode = .copy,
        .is_template = true,
    };
    try std.testing.expectEqualStrings(".gitconfig", f.target_rel);
    try std.testing.expect(f.is_template);
}
