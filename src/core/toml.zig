const std = @import("std");
const Allocator = std.mem.Allocator;

/// A TOML value: string, boolean, or integer.
pub const Value = union(enum) {
    string: []const u8,
    boolean: bool,
    integer: i64,
};

/// Represents a single TOML table (section).
pub const Table = struct {
    values: std.StringHashMap(Value),

    pub fn init(allocator: Allocator) Table {
        return .{ .values = std.StringHashMap(Value).init(allocator) };
    }

    pub fn deinit(self: *Table) void {
        var it = self.values.iterator();
        while (it.next()) |entry| {
            self.values.allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .string => |s| self.values.allocator.free(s),
                else => {},
            }
        }
        self.values.deinit();
    }

    pub fn getString(self: *const Table, key: []const u8) ?[]const u8 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    pub fn getBool(self: *const Table, key: []const u8) ?bool {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .boolean => |b| b,
                else => null,
            };
        }
        return null;
    }

    pub fn getInt(self: *const Table, key: []const u8) ?i64 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .integer => |i| i,
                else => null,
            };
        }
        return null;
    }
};

/// An entry from an array of tables ([[section]]).
pub const ArrayTable = struct {
    values: std.StringHashMap(Value),

    pub fn init(allocator: Allocator) ArrayTable {
        return .{ .values = std.StringHashMap(Value).init(allocator) };
    }

    pub fn deinit(self: *ArrayTable) void {
        var it = self.values.iterator();
        while (it.next()) |entry| {
            self.values.allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .string => |s| self.values.allocator.free(s),
                else => {},
            }
        }
        self.values.deinit();
    }

    pub fn getString(self: *const ArrayTable, key: []const u8) ?[]const u8 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    pub fn getBool(self: *const ArrayTable, key: []const u8) ?bool {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .boolean => |b| b,
                else => null,
            };
        }
        return null;
    }
};

/// Growable list of ArrayTable that stores its own allocator.
const ArrayTableList = struct {
    items: []ArrayTable,
    capacity: usize,
    allocator: Allocator,

    fn init(allocator: Allocator) ArrayTableList {
        return .{ .items = &.{}, .capacity = 0, .allocator = allocator };
    }

    fn append(self: *ArrayTableList, item: ArrayTable) Allocator.Error!void {
        if (self.items.len >= self.capacity) {
            const new_cap = if (self.capacity == 0) @as(usize, 4) else self.capacity * 2;
            const new_buf = try self.allocator.alloc(ArrayTable, new_cap);
            if (self.items.len > 0) {
                @memcpy(new_buf[0..self.items.len], self.items);
                self.allocator.free(self.items);
            }
            self.items.ptr = new_buf.ptr;
            self.capacity = new_cap;
        }
        self.items.len += 1;
        self.items[self.items.len - 1] = item;
    }

    fn deinit(self: *ArrayTableList) void {
        for (self.items) |*item| {
            item.deinit();
        }
        if (self.capacity > 0) {
            self.allocator.free(self.items.ptr[0..self.capacity]);
        }
        self.* = undefined;
    }
};

/// Result of parsing a TOML document.
pub const Document = struct {
    allocator: Allocator,
    tables: std.StringHashMap(Table),
    array_tables: std.StringHashMap(ArrayTableList),

    pub fn init(allocator: Allocator) Document {
        return .{
            .allocator = allocator,
            .tables = std.StringHashMap(Table).init(allocator),
            .array_tables = std.StringHashMap(ArrayTableList).init(allocator),
        };
    }

    pub fn deinit(self: *Document) void {
        var tit = self.tables.iterator();
        while (tit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.tables.deinit();

        var ait = self.array_tables.iterator();
        while (ait.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.array_tables.deinit();
    }

    pub fn getTable(self: *const Document, name: []const u8) ?*const Table {
        return self.tables.getPtr(name);
    }

    pub fn getArrayTable(self: *const Document, name: []const u8) ?[]const ArrayTable {
        if (self.array_tables.getPtr(name)) |list| {
            return list.items;
        }
        return null;
    }
};

pub const ParseError = error{
    UnexpectedToken,
    UnterminatedString,
    InvalidNumber,
    OutOfMemory,
};

/// Parse a TOML document from source text.
pub fn parse(allocator: Allocator, source: []const u8) ParseError!Document {
    var doc = Document.init(allocator);
    errdefer doc.deinit();

    var current_section: []const u8 = "";
    var is_array_section = false;

    var line_start: usize = 0;
    while (line_start < source.len) {
        const line_end = std.mem.indexOfScalar(u8, source[line_start..], '\n') orelse source.len - line_start;
        const raw_line = source[line_start .. line_start + line_end];
        line_start += line_end + 1;

        const line = std.mem.trim(u8, raw_line, " \t\r");

        // Skip empty lines and comments
        if (line.len == 0 or line[0] == '#') continue;

        // Array of tables: [[section]]
        if (line.len >= 4 and line[0] == '[' and line[1] == '[') {
            const close = std.mem.indexOf(u8, line, "]]") orelse continue;
            const name = std.mem.trim(u8, line[2..close], " \t");
            const name_dupe = try allocator.dupe(u8, name);

            is_array_section = true;

            const gop = try doc.array_tables.getOrPut(name_dupe);
            if (!gop.found_existing) {
                gop.value_ptr.* = ArrayTableList.init(allocator);
            } else {
                allocator.free(name_dupe);
            }
            current_section = gop.key_ptr.*;
            try gop.value_ptr.append(ArrayTable.init(allocator));
            continue;
        }

        // Table: [section]
        if (line[0] == '[') {
            const close = std.mem.indexOfScalar(u8, line, ']') orelse continue;
            const name = std.mem.trim(u8, line[1..close], " \t");
            const name_dupe = try allocator.dupe(u8, name);
            is_array_section = false;

            const gop = try doc.tables.getOrPut(name_dupe);
            if (!gop.found_existing) {
                gop.value_ptr.* = Table.init(allocator);
            } else {
                allocator.free(name_dupe);
            }
            current_section = gop.key_ptr.*;
            continue;
        }

        // Key = value
        const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_pos], " \t");
        const raw_val = std.mem.trim(u8, line[eq_pos + 1 ..], " \t");

        const value = try parseValue(allocator, raw_val);
        const key_dupe = try allocator.dupe(u8, key);

        if (is_array_section) {
            if (doc.array_tables.getPtr(current_section)) |list| {
                if (list.items.len > 0) {
                    try list.items[list.items.len - 1].values.put(key_dupe, value);
                }
            }
        } else if (current_section.len > 0) {
            if (doc.tables.getPtr(current_section)) |table| {
                try table.values.put(key_dupe, value);
            }
        } else {
            const gop = try doc.tables.getOrPut("");
            if (!gop.found_existing) {
                gop.value_ptr.* = Table.init(allocator);
            }
            try gop.value_ptr.values.put(key_dupe, value);
        }
    }

    return doc;
}

fn parseValue(allocator: Allocator, raw: []const u8) ParseError!Value {
    if (raw.len == 0) return error.UnexpectedToken;

    // String: "..."
    if (raw[0] == '"') {
        const end = std.mem.indexOfScalarPos(u8, raw, 1, '"') orelse return error.UnterminatedString;
        return .{ .string = try allocator.dupe(u8, raw[1..end]) };
    }

    // Boolean
    if (std.mem.eql(u8, raw, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, raw, "false")) return .{ .boolean = false };

    // Integer
    const val = std.fmt.parseInt(i64, raw, 10) catch return error.InvalidNumber;
    return .{ .integer = val };
}

// === Tests ===

test "parse simple key-value pairs in a section" {
    const source =
        \\[settings]
        \\default_mode = "symlink"
        \\git_auto_commit = false
        \\
    ;

    var doc = try parse(std.testing.allocator, source);
    defer doc.deinit();

    const settings = doc.getTable("settings").?;
    try std.testing.expectEqualStrings("symlink", settings.getString("default_mode").?);
    try std.testing.expectEqual(false, settings.getBool("git_auto_commit").?);
}

test "parse variables section with mixed types" {
    const source =
        \\[variables]
        \\hostname = "myhost"
        \\email = "user@example.com"
        \\is_work = false
        \\
    ;

    var doc = try parse(std.testing.allocator, source);
    defer doc.deinit();

    const vars = doc.getTable("variables").?;
    try std.testing.expectEqualStrings("myhost", vars.getString("hostname").?);
    try std.testing.expectEqualStrings("user@example.com", vars.getString("email").?);
    try std.testing.expectEqual(false, vars.getBool("is_work").?);
}

test "parse array of tables" {
    const source =
        \\[[files]]
        \\path = ".bashrc"
        \\mode = "copy"
        \\
        \\[[files]]
        \\path = ".ssh/config"
        \\mode = "copy"
        \\template = true
        \\
    ;

    var doc = try parse(std.testing.allocator, source);
    defer doc.deinit();

    const files = doc.getArrayTable("files").?;
    try std.testing.expectEqual(@as(usize, 2), files.len);
    try std.testing.expectEqualStrings(".bashrc", files[0].getString("path").?);
    try std.testing.expectEqualStrings("copy", files[0].getString("mode").?);
    try std.testing.expectEqualStrings(".ssh/config", files[1].getString("path").?);
    try std.testing.expectEqual(true, files[1].getBool("template").?);
}

test "parse integer values" {
    const source =
        \\[perpet]
        \\version = 1
        \\
    ;

    var doc = try parse(std.testing.allocator, source);
    defer doc.deinit();

    const perpet_section = doc.getTable("perpet").?;
    try std.testing.expectEqual(@as(i64, 1), perpet_section.getInt("version").?);
}

test "skip comments and empty lines" {
    const source =
        \\# This is a comment
        \\
        \\[settings]
        \\# Another comment
        \\default_mode = "symlink"
        \\
    ;

    var doc = try parse(std.testing.allocator, source);
    defer doc.deinit();

    const settings = doc.getTable("settings").?;
    try std.testing.expectEqualStrings("symlink", settings.getString("default_mode").?);
}

test "parse full perpet.toml example" {
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
        \\email = "user@example.com"
        \\name = "Jane Doe"
        \\is_work = false
        \\
        \\[[files]]
        \\path = ".bashrc"
        \\mode = "copy"
        \\
        \\[[files]]
        \\path = ".ssh/config"
        \\mode = "copy"
        \\
    ;

    var doc = try parse(std.testing.allocator, source);
    defer doc.deinit();

    try std.testing.expectEqual(@as(i64, 1), doc.getTable("perpet").?.getInt("version").?);

    const settings = doc.getTable("settings").?;
    try std.testing.expectEqualStrings("symlink", settings.getString("default_mode").?);
    try std.testing.expectEqualStrings("", settings.getString("editor").?);
    try std.testing.expectEqual(false, settings.getBool("git_auto_commit").?);
    try std.testing.expectEqualStrings("origin", settings.getString("git_remote").?);

    const vars = doc.getTable("variables").?;
    try std.testing.expectEqualStrings("Jane Doe", vars.getString("name").?);

    const files = doc.getArrayTable("files").?;
    try std.testing.expectEqual(@as(usize, 2), files.len);
    try std.testing.expectEqualStrings(".bashrc", files[0].getString("path").?);
}

test "unterminated string returns error" {
    const source =
        \\[settings]
        \\name = "unterminated
        \\
    ;

    const result = parse(std.testing.allocator, source);
    try std.testing.expectError(error.UnterminatedString, result);
}
