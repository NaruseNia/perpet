const std = @import("std");
const Allocator = std.mem.Allocator;
const toml = @import("toml.zig");
const paths = @import("paths.zig");

pub const FileMode = enum {
    symlink,
    copy,
};

pub const FileEntry = struct {
    path: []const u8,
    mode: ?FileMode,
    template: ?bool,
};

pub const Config = struct {
    allocator: Allocator,

    // [perpet]
    version: i64,

    // [settings]
    default_mode: FileMode,
    editor: []const u8,
    git_auto_commit: bool,
    git_remote: []const u8,

    // [variables]
    variables: std.StringHashMap([]const u8),

    // [[files]]
    files: []FileEntry,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.editor);
        self.allocator.free(self.git_remote);

        var vit = self.variables.iterator();
        while (vit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.variables.deinit();

        for (self.files) |f| {
            self.allocator.free(f.path);
        }
        self.allocator.free(self.files);
    }
};

/// Load config from a TOML document.
pub fn loadFromDoc(allocator: Allocator, doc: *const toml.Document) !Config {
    // [perpet]
    const version = if (doc.getTable("perpet")) |t| t.getInt("version") orelse 1 else 1;

    // [settings]
    const settings = doc.getTable("settings");

    const default_mode: FileMode = blk: {
        if (settings) |s| {
            if (s.getString("default_mode")) |m| {
                if (std.mem.eql(u8, m, "copy")) break :blk .copy;
            }
        }
        break :blk .symlink;
    };

    const editor = try allocator.dupe(u8, if (settings) |s| s.getString("editor") orelse "" else "");
    const git_auto_commit = if (settings) |s| s.getBool("git_auto_commit") orelse false else false;
    const git_remote = try allocator.dupe(u8, if (settings) |s| s.getString("git_remote") orelse "origin" else "origin");

    // [variables]
    var variables = std.StringHashMap([]const u8).init(allocator);

    // Auto-detected variables
    try variables.put(try allocator.dupe(u8, "os"), try allocator.dupe(u8, paths.getOsName()));
    try variables.put(try allocator.dupe(u8, "arch"), try allocator.dupe(u8, paths.getArchName()));

    if (doc.getTable("variables")) |vars_table| {
        var it = vars_table.values.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const val = switch (entry.value_ptr.*) {
                .string => |s| try allocator.dupe(u8, s),
                .boolean => |b| try allocator.dupe(u8, if (b) "true" else "false"),
                .integer => |i| blk: {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
                    break :blk try allocator.dupe(u8, s);
                },
            };
            // User variables override auto-detected ones
            if (variables.getPtr(key)) |existing| {
                allocator.free(existing.*);
                existing.* = val;
                allocator.free(key);
            } else {
                try variables.put(key, val);
            }
        }
    }

    // [[files]]
    var file_list: std.ArrayList(FileEntry) = .empty;
    defer file_list.deinit(allocator);

    if (doc.getArrayTable("files")) |entries| {
        for (entries) |entry| {
            const path_val = entry.getString("path") orelse continue;
            const mode: ?FileMode = blk: {
                if (entry.getString("mode")) |m| {
                    if (std.mem.eql(u8, m, "copy")) break :blk .copy;
                    if (std.mem.eql(u8, m, "symlink")) break :blk .symlink;
                }
                break :blk null;
            };
            const tmpl = entry.getBool("template");

            try file_list.append(allocator, .{
                .path = try allocator.dupe(u8, path_val),
                .mode = mode,
                .template = tmpl,
            });
        }
    }

    return .{
        .allocator = allocator,
        .version = version,
        .default_mode = default_mode,
        .editor = editor,
        .git_auto_commit = git_auto_commit,
        .git_remote = git_remote,
        .variables = variables,
        .files = try file_list.toOwnedSlice(allocator),
    };
}

/// Load config from a TOML source string.
pub fn loadFromString(allocator: Allocator, source: []const u8) !Config {
    var doc = try toml.parse(allocator, source);
    defer doc.deinit();
    return loadFromDoc(allocator, &doc);
}

/// Load config from the default perpet.toml file.
/// Returns a default config if the file does not exist.
pub fn load(allocator: Allocator) !Config {
    const config_path = try paths.getConfigPath(allocator);
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch {
        return defaults(allocator);
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    return loadFromString(allocator, content);
}

/// Returns a default config with no files and auto-detected variables.
pub fn defaults(allocator: Allocator) !Config {
    var variables = std.StringHashMap([]const u8).init(allocator);
    try variables.put(try allocator.dupe(u8, "os"), try allocator.dupe(u8, paths.getOsName()));
    try variables.put(try allocator.dupe(u8, "arch"), try allocator.dupe(u8, paths.getArchName()));

    return .{
        .allocator = allocator,
        .version = 1,
        .default_mode = .symlink,
        .editor = try allocator.dupe(u8, ""),
        .git_auto_commit = false,
        .git_remote = try allocator.dupe(u8, "origin"),
        .variables = variables,
        .files = try allocator.alloc(FileEntry, 0),
    };
}

/// Generate TOML source string from a Config.
pub fn serialize(allocator: Allocator, cfg: *const Config) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll("[perpet]\nversion = ");
    try std.fmt.format(w, "{d}", .{cfg.version});
    try w.writeAll("\n\n[settings]\ndefault_mode = \"");
    try w.writeAll(if (cfg.default_mode == .copy) "copy" else "symlink");
    try w.writeAll("\"\neditor = \"");
    try w.writeAll(cfg.editor);
    try w.writeAll("\"\ngit_auto_commit = ");
    try w.writeAll(if (cfg.git_auto_commit) "true" else "false");
    try w.writeAll("\ngit_remote = \"");
    try w.writeAll(cfg.git_remote);
    try w.writeAll("\"\n\n[variables]\n");

    // Write variables (skip auto-detected os/arch)
    var vit = cfg.variables.iterator();
    while (vit.next()) |entry| {
        const val = entry.value_ptr.*;
        if (std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "false")) {
            try std.fmt.format(w, "{s} = {s}\n", .{ entry.key_ptr.*, val });
        } else {
            try std.fmt.format(w, "{s} = \"{s}\"\n", .{ entry.key_ptr.*, val });
        }
    }

    // Write file entries
    for (cfg.files) |f| {
        try w.writeAll("\n[[files]]\npath = \"");
        try w.writeAll(f.path);
        try w.writeAll("\"");
        if (f.mode) |m| {
            try w.writeAll("\nmode = \"");
            try w.writeAll(if (m == .copy) "copy" else "symlink");
            try w.writeAll("\"");
        }
        if (f.template) |t| {
            try w.writeAll("\ntemplate = ");
            try w.writeAll(if (t) "true" else "false");
        }
        try w.writeAll("\n");
    }

    return buf.toOwnedSlice(allocator);
}

// === Tests ===

test "loadFromString with full config" {
    const source =
        \\[perpet]
        \\version = 1
        \\
        \\[settings]
        \\default_mode = "copy"
        \\editor = "vim"
        \\git_auto_commit = true
        \\git_remote = "upstream"
        \\
        \\[variables]
        \\hostname = "myhost"
        \\is_work = true
        \\
        \\[[files]]
        \\path = ".bashrc"
        \\mode = "copy"
        \\
    ;

    var cfg = try loadFromString(std.testing.allocator, source);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(i64, 1), cfg.version);
    try std.testing.expectEqual(FileMode.copy, cfg.default_mode);
    try std.testing.expectEqualStrings("vim", cfg.editor);
    try std.testing.expectEqual(true, cfg.git_auto_commit);
    try std.testing.expectEqualStrings("upstream", cfg.git_remote);
    try std.testing.expectEqualStrings("myhost", cfg.variables.get("hostname").?);
    try std.testing.expectEqualStrings("true", cfg.variables.get("is_work").?);
    try std.testing.expectEqual(@as(usize, 1), cfg.files.len);
    try std.testing.expectEqualStrings(".bashrc", cfg.files[0].path);
    try std.testing.expectEqual(FileMode.copy, cfg.files[0].mode.?);
}

test "loadFromString with minimal config" {
    const source =
        \\[perpet]
        \\version = 1
        \\
    ;

    var cfg = try loadFromString(std.testing.allocator, source);
    defer cfg.deinit();

    try std.testing.expectEqual(FileMode.symlink, cfg.default_mode);
    try std.testing.expectEqualStrings("", cfg.editor);
    try std.testing.expectEqual(false, cfg.git_auto_commit);
    try std.testing.expectEqual(@as(usize, 0), cfg.files.len);
    // Auto-detected variables should be present
    try std.testing.expect(cfg.variables.get("os") != null);
    try std.testing.expect(cfg.variables.get("arch") != null);
}

test "defaults returns valid config" {
    var cfg = try defaults(std.testing.allocator);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(i64, 1), cfg.version);
    try std.testing.expectEqual(FileMode.symlink, cfg.default_mode);
    try std.testing.expectEqual(@as(usize, 0), cfg.files.len);
    try std.testing.expect(cfg.variables.get("os") != null);
}

test "serialize roundtrip" {
    const source =
        \\[perpet]
        \\version = 1
        \\
        \\[settings]
        \\default_mode = "symlink"
        \\editor = ""
        \\git_auto_commit = false
        \\git_remote = "origin"
        \\
        \\[variables]
        \\hostname = "myhost"
        \\
        \\[[files]]
        \\path = ".bashrc"
        \\mode = "copy"
        \\
    ;

    var cfg = try loadFromString(std.testing.allocator, source);
    defer cfg.deinit();

    const serialized = try serialize(std.testing.allocator, &cfg);
    defer std.testing.allocator.free(serialized);

    // Parse the serialized output and verify key values survive roundtrip
    var cfg2 = try loadFromString(std.testing.allocator, serialized);
    defer cfg2.deinit();

    try std.testing.expectEqual(cfg.version, cfg2.version);
    try std.testing.expectEqual(cfg.default_mode, cfg2.default_mode);
    try std.testing.expectEqual(cfg.git_auto_commit, cfg2.git_auto_commit);
    try std.testing.expectEqualStrings("myhost", cfg2.variables.get("hostname").?);
    try std.testing.expectEqual(cfg.files.len, cfg2.files.len);
}
