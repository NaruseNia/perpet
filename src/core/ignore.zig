const std = @import("std");
const Allocator = std.mem.Allocator;
const paths = @import("paths.zig");
const fs_ops = @import("fs_ops.zig");

const PatternKind = enum {
    exact, // ".DS_Store" — matches basename anywhere
    glob, // "*.log" — wildcard match on basename
    dir_prefix, // "node_modules/" — matches directory prefix
    doublestar, // "**/build" — matches at any depth
};

const Pattern = struct {
    kind: PatternKind,
    text: []const u8,
};

pub const IgnoreList = struct {
    patterns: []const Pattern,
    _content: ?[]const u8,
    _patterns_buf: ?[]const Pattern,

    pub fn matches(self: *const IgnoreList, rel_path: []const u8) bool {
        for (self.patterns) |pat| {
            if (matchPattern(pat, rel_path)) return true;
        }
        return false;
    }

    pub fn deinit(self: *IgnoreList, allocator: Allocator) void {
        if (self._patterns_buf) |buf| allocator.free(buf);
        if (self._content) |c| allocator.free(c);
        self._patterns_buf = null;
        self._content = null;
        self.patterns = &.{};
    }
};

fn matchPattern(pat: Pattern, rel_path: []const u8) bool {
    const basename = std.fs.path.basename(rel_path);
    return switch (pat.kind) {
        .exact => std.mem.eql(u8, basename, pat.text),
        .glob => globMatch(pat.text, basename),
        .dir_prefix => matchDirPrefix(pat.text, rel_path),
        .doublestar => matchDoublestar(pat.text, rel_path),
    };
}

fn matchDirPrefix(prefix: []const u8, rel_path: []const u8) bool {
    // "node_modules" matches "node_modules/foo.js" or "a/node_modules/bar.js"
    if (std.mem.startsWith(u8, rel_path, prefix)) {
        if (rel_path.len > prefix.len and rel_path[prefix.len] == '/') return true;
        if (rel_path.len == prefix.len) return true;
    }
    // Check for /prefix/ anywhere in path
    const needle = std.fmt.comptimePrint("", .{}); // can't use comptime here
    _ = needle;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, rel_path, i, "/")) |pos| {
        const after = pos + 1;
        if (std.mem.startsWith(u8, rel_path[after..], prefix)) {
            const end = after + prefix.len;
            if (end == rel_path.len or rel_path[end] == '/') return true;
        }
        i = after;
    }
    return false;
}

fn matchDoublestar(suffix: []const u8, rel_path: []const u8) bool {
    // "**/build" with suffix="build"
    // Match if basename equals suffix, or if path ends with /suffix,
    // or if suffix contains / and path ends with that suffix
    if (std.mem.eql(u8, rel_path, suffix)) return true;

    if (std.mem.indexOf(u8, suffix, "/")) |_| {
        // suffix has path components, e.g. "build/output"
        if (std.mem.endsWith(u8, rel_path, suffix)) {
            if (rel_path.len == suffix.len) return true;
            if (rel_path[rel_path.len - suffix.len - 1] == '/') return true;
        }
    } else {
        // suffix is a single name, match any path component
        const basename = std.fs.path.basename(rel_path);
        if (std.mem.eql(u8, basename, suffix)) return true;
        // Also check as directory component
        if (matchDirPrefix(suffix, rel_path)) return true;
    }
    return false;
}

fn globMatch(pattern: []const u8, text: []const u8) bool {
    // Simple glob: split pattern on '*', match segments in order
    // '*' matches anything except '/'
    var pat_pos: usize = 0;
    var txt_pos: usize = 0;

    // Find segments between '*'
    var first = true;
    var last_star = false;

    while (pat_pos <= pattern.len) {
        // Find next '*'
        const star_pos = std.mem.indexOfPos(u8, pattern, pat_pos, "*");
        const segment = if (star_pos) |sp| pattern[pat_pos..sp] else pattern[pat_pos..];

        if (segment.len > 0) {
            if (first and star_pos == null) {
                // No '*' at all — exact match
                return std.mem.eql(u8, pattern, text);
            }

            if (first and pat_pos == 0) {
                // Pattern doesn't start with '*', segment must be at start
                if (!std.mem.startsWith(u8, text[txt_pos..], segment)) return false;
                txt_pos += segment.len;
            } else if (star_pos == null) {
                // Last segment (after last '*'), must match at end
                if (text.len < segment.len) return false;
                if (!std.mem.endsWith(u8, text, segment)) return false;
                // Ensure no '/' in the gap
                const gap_end = text.len - segment.len;
                if (txt_pos < gap_end) {
                    if (std.mem.indexOf(u8, text[txt_pos..gap_end], "/") != null) return false;
                }
                return true;
            } else {
                // Middle segment — find it in remaining text (no '/' crossing)
                const found = std.mem.indexOfPos(u8, text, txt_pos, segment) orelse return false;
                // Check no '/' between current pos and found
                if (std.mem.indexOf(u8, text[txt_pos..found], "/") != null) return false;
                txt_pos = found + segment.len;
            }
        }

        first = false;
        if (star_pos) |sp| {
            pat_pos = sp + 1;
            last_star = true;
        } else {
            break;
        }
    }

    if (last_star) {
        // Pattern ends with '*', remaining text must not contain '/'
        if (txt_pos < text.len) {
            return std.mem.indexOf(u8, text[txt_pos..], "/") == null;
        }
    }

    return txt_pos == text.len;
}

/// Load .perpetignore from the perpet source directory.
/// Returns an empty IgnoreList if the file doesn't exist.
pub fn load(allocator: Allocator) !IgnoreList {
    const source_dir = try paths.getSourceDir(allocator);
    defer allocator.free(source_dir);
    return loadFromDir(allocator, source_dir);
}

/// Load .perpetignore from a given directory.
pub fn loadFromDir(allocator: Allocator, dir: []const u8) !IgnoreList {
    const ignore_path = try std.fs.path.join(allocator, &.{ dir, ".perpetignore" });
    defer allocator.free(ignore_path);

    const content = fs_ops.readFile(allocator, ignore_path) catch {
        return .{
            .patterns = &.{},
            ._content = null,
            ._patterns_buf = null,
        };
    };

    return parse(allocator, content);
}

/// Parse raw content into an IgnoreList. Takes ownership of content.
pub fn parse(allocator: Allocator, content: []const u8) !IgnoreList {
    // Pass 1: count valid patterns
    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        count += 1;
    }

    if (count == 0) {
        return .{
            .patterns = &.{},
            ._content = content,
            ._patterns_buf = null,
        };
    }

    // Pass 2: populate patterns
    const patterns = try allocator.alloc(Pattern, count);
    var idx: usize = 0;
    iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        if (std.mem.startsWith(u8, line, "**/")) {
            patterns[idx] = .{ .kind = .doublestar, .text = line[3..] };
        } else if (std.mem.endsWith(u8, line, "/")) {
            patterns[idx] = .{ .kind = .dir_prefix, .text = line[0 .. line.len - 1] };
        } else if (std.mem.indexOf(u8, line, "*") != null) {
            patterns[idx] = .{ .kind = .glob, .text = line };
        } else {
            patterns[idx] = .{ .kind = .exact, .text = line };
        }
        idx += 1;
    }

    return .{
        .patterns = patterns,
        ._content = content,
        ._patterns_buf = patterns,
    };
}

// === Tests ===

test "empty content matches nothing" {
    const content = try std.testing.allocator.dupe(u8, "");
    var list = try parse(std.testing.allocator, content);
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(!list.matches("foo.txt"));
}

test "comments and blank lines are skipped" {
    const content = try std.testing.allocator.dupe(u8, "# comment\n\n  \n# another\n");
    var list = try parse(std.testing.allocator, content);
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(list.patterns.len == 0);
}

test "exact match on basename" {
    const content = try std.testing.allocator.dupe(u8, ".DS_Store\n");
    var list = try parse(std.testing.allocator, content);
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(list.matches(".DS_Store"));
    try std.testing.expect(list.matches("subdir/.DS_Store"));
    try std.testing.expect(!list.matches(".DS_Store_other"));
    try std.testing.expect(!list.matches("file.txt"));
}

test "glob *.log matches .log files" {
    const content = try std.testing.allocator.dupe(u8, "*.log\n");
    var list = try parse(std.testing.allocator, content);
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(list.matches("app.log"));
    try std.testing.expect(list.matches("sub/debug.log"));
    try std.testing.expect(!list.matches("logfile.txt"));
    try std.testing.expect(!list.matches("app.log.bak"));
}

test "dir_prefix node_modules/ matches nested paths" {
    const content = try std.testing.allocator.dupe(u8, "node_modules/\n");
    var list = try parse(std.testing.allocator, content);
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(list.matches("node_modules/foo.js"));
    try std.testing.expect(list.matches("a/node_modules/bar.js"));
    try std.testing.expect(!list.matches("my_node_modules/foo.js"));
    try std.testing.expect(!list.matches("node_modules_extra/foo.js"));
}

test "doublestar **/build matches at any depth" {
    const content = try std.testing.allocator.dupe(u8, "**/build\n");
    var list = try parse(std.testing.allocator, content);
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(list.matches("build"));
    try std.testing.expect(list.matches("src/build"));
    try std.testing.expect(list.matches("a/b/build"));
    try std.testing.expect(!list.matches("build-tools"));
}

test "glob with prefix and suffix" {
    const content = try std.testing.allocator.dupe(u8, "test_*.txt\n");
    var list = try parse(std.testing.allocator, content);
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(list.matches("test_foo.txt"));
    try std.testing.expect(list.matches("dir/test_bar.txt"));
    try std.testing.expect(!list.matches("test_foo.log"));
    try std.testing.expect(!list.matches("my_test_foo.txt"));
}

test "multiple patterns" {
    const content = try std.testing.allocator.dupe(u8, "# Ignore these\n.DS_Store\nnode_modules/\n*.log\n");
    var list = try parse(std.testing.allocator, content);
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(list.patterns.len == 3);
    try std.testing.expect(list.matches(".DS_Store"));
    try std.testing.expect(list.matches("node_modules/package.json"));
    try std.testing.expect(list.matches("error.log"));
    try std.testing.expect(!list.matches("readme.md"));
}
