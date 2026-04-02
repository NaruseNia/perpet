const std = @import("std");
const Allocator = std.mem.Allocator;

pub const RenderError = error{
    UnterminatedTag,
    UnterminatedBlock,
    InvalidDirective,
    OutOfMemory,
};

/// Render a template string with variable substitution and conditionals.
///
/// Supported syntax:
///   {{ .variable }}          - variable substitution
///   {{ if .cond }}...{{ end }}  - conditional block
///   {{ if .cond }}...{{ else }}...{{ end }} - if/else
///   {{ if not .cond }}...{{ end }} - negated conditional
pub fn render(allocator: Allocator, template: []const u8, variables: std.StringHashMap([]const u8)) RenderError![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var pos: usize = 0;
    var cond_stack: [16]CondFrame = undefined;
    var cond_depth: usize = 0;

    while (pos < template.len) {
        // Look for {{
        if (pos + 1 < template.len and template[pos] == '{' and template[pos + 1] == '{') {
            const tag_start = pos;
            const close = findClose(template, pos + 2) orelse return error.UnterminatedTag;
            const inner = std.mem.trim(u8, template[pos + 2 .. close], " \t");
            pos = close + 2; // skip }}

            // Check if we're in a skipped block
            const should_output = !isSkipping(&cond_stack, cond_depth);

            if (inner.len >= 3 and std.mem.startsWith(u8, inner, "if ")) {
                // {{ if .cond }} or {{ if not .cond }}
                const cond_expr = std.mem.trim(u8, inner[3..], " \t");
                const negated = std.mem.startsWith(u8, cond_expr, "not ");
                const var_part = if (negated) std.mem.trim(u8, cond_expr[4..], " \t") else cond_expr;
                const var_name = if (std.mem.startsWith(u8, var_part, ".")) var_part[1..] else var_part;

                const truthy = if (should_output) isTruthy(variables, var_name) else false;
                const effective = if (negated) !truthy else truthy;

                if (cond_depth >= cond_stack.len) return error.UnterminatedBlock;
                cond_stack[cond_depth] = .{
                    .active = effective and should_output,
                    .parent_active = should_output,
                    .seen_else = false,
                };
                cond_depth += 1;
            } else if (std.mem.eql(u8, inner, "else")) {
                if (cond_depth == 0) return error.InvalidDirective;
                const frame = &cond_stack[cond_depth - 1];
                frame.seen_else = true;
                frame.active = !frame.active and frame.parent_active;
            } else if (std.mem.eql(u8, inner, "end")) {
                if (cond_depth == 0) return error.InvalidDirective;
                cond_depth -= 1;
            } else if (inner.len > 0 and inner[0] == '.') {
                // {{ .variable }}
                if (should_output) {
                    const var_name = inner[1..];
                    if (variables.get(var_name)) |val| {
                        try output.appendSlice(allocator, val);
                    }
                }
            } else {
                // Unknown directive, output as-is if not skipping
                if (should_output) {
                    try output.appendSlice(allocator, template[tag_start..pos]);
                }
            }
        } else {
            if (!isSkipping(&cond_stack, cond_depth)) {
                try output.append(allocator, template[pos]);
            }
            pos += 1;
        }
    }

    if (cond_depth > 0) return error.UnterminatedBlock;

    return output.toOwnedSlice(allocator);
}

const CondFrame = struct {
    active: bool,
    parent_active: bool,
    seen_else: bool,
};

fn isSkipping(stack: []const CondFrame, depth: usize) bool {
    if (depth == 0) return false;
    return !stack[depth - 1].active;
}

fn isTruthy(variables: std.StringHashMap([]const u8), name: []const u8) bool {
    const val = variables.get(name) orelse return false;
    if (val.len == 0) return false;
    if (std.mem.eql(u8, val, "false")) return false;
    if (std.mem.eql(u8, val, "0")) return false;
    return true;
}

fn findClose(template: []const u8, start: usize) ?usize {
    var i = start;
    while (i + 1 < template.len) : (i += 1) {
        if (template[i] == '}' and template[i + 1] == '}') return i;
    }
    return null;
}

// === Tests ===

fn testVars(allocator: Allocator, pairs: []const struct { []const u8, []const u8 }) std.StringHashMap([]const u8) {
    var map = std.StringHashMap([]const u8).init(allocator);
    for (pairs) |pair| {
        map.put(pair[0], pair[1]) catch unreachable;
    }
    return map;
}

test "simple variable substitution" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "name", "Jane" },
        .{ "email", "jane@example.com" },
    });
    defer vars.deinit();

    const result = try render(std.testing.allocator, "Hello {{ .name }}, your email is {{ .email }}", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("Hello Jane, your email is jane@example.com", result);
}

test "undefined variable renders empty" {
    var vars = testVars(std.testing.allocator, &.{});
    defer vars.deinit();

    const result = try render(std.testing.allocator, "Hello {{ .name }}", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("Hello ", result);
}

test "if true block" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "is_work", "true" },
    });
    defer vars.deinit();

    const result = try render(std.testing.allocator, "{{ if .is_work }}WORK{{ end }}", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("WORK", result);
}

test "if false block" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "is_work", "false" },
    });
    defer vars.deinit();

    const result = try render(std.testing.allocator, "{{ if .is_work }}WORK{{ end }}", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "if/else block" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "is_work", "false" },
    });
    defer vars.deinit();

    const result = try render(std.testing.allocator, "{{ if .is_work }}work{{ else }}personal{{ end }}", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("personal", result);
}

test "if not block" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "is_work", "false" },
    });
    defer vars.deinit();

    const result = try render(std.testing.allocator, "{{ if not .is_work }}HOME{{ end }}", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("HOME", result);
}

test "nested if blocks" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "a", "true" },
        .{ "b", "true" },
    });
    defer vars.deinit();

    const result = try render(std.testing.allocator, "{{ if .a }}A{{ if .b }}B{{ end }}{{ end }}", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("AB", result);
}

test "nested if with outer false" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "a", "false" },
        .{ "b", "true" },
    });
    defer vars.deinit();

    const result = try render(std.testing.allocator, "{{ if .a }}A{{ if .b }}B{{ end }}{{ end }}", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "realistic gitconfig template" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "name", "Jane Doe" },
        .{ "email", "jane@work.com" },
        .{ "is_work", "true" },
    });
    defer vars.deinit();

    const tmpl =
        \\[user]
        \\    name = {{ .name }}
        \\    email = {{ .email }}
        \\{{ if .is_work }}[url "git@github-work:"]
        \\    insteadOf = https://github.com/
        \\{{ end }}
    ;

    const result = try render(std.testing.allocator, tmpl, vars);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "Jane Doe") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "github-work") != null);
}

test "unterminated tag returns error" {
    var vars = testVars(std.testing.allocator, &.{});
    defer vars.deinit();

    const result = render(std.testing.allocator, "Hello {{ .name", vars);
    try std.testing.expectError(error.UnterminatedTag, result);
}

test "unterminated block returns error" {
    var vars = testVars(std.testing.allocator, &.{
        .{ "x", "true" },
    });
    defer vars.deinit();

    const result = render(std.testing.allocator, "{{ if .x }}hello", vars);
    try std.testing.expectError(error.UnterminatedBlock, result);
}

test "no template tags returns input unchanged" {
    var vars = testVars(std.testing.allocator, &.{});
    defer vars.deinit();

    const result = try render(std.testing.allocator, "plain text file\nno templates here\n", vars);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("plain text file\nno templates here\n", result);
}
