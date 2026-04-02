const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const filter_path = args.next();

    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("perpet diff: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const files = core.manifest.enumerate(allocator, &cfg) catch |err| {
        cli.printErr("perpet diff: failed to enumerate files: {}\n", .{err});
        std.process.exit(1);
    };
    defer core.manifest.freeFiles(allocator, files);

    var found = false;
    for (files) |file| {
        if (filter_path) |fp| {
            if (!std.mem.eql(u8, file.target_rel, fp)) continue;
        }

        const source_path = core.paths.resolveSourcePath(allocator, file.source_rel) catch continue;
        defer allocator.free(source_path);
        const target_path = core.paths.resolveTargetPath(allocator, file.source_rel) catch continue;
        defer allocator.free(target_path);

        // Get source content (rendered if template)
        var source_content: []const u8 = undefined;
        var source_allocated = false;

        if (file.is_template) {
            const raw = core.fs_ops.readFile(allocator, source_path) catch continue;
            defer allocator.free(raw);
            source_content = core.template.render(allocator, raw, cfg.variables) catch continue;
            source_allocated = true;
        } else {
            source_content = core.fs_ops.readFile(allocator, source_path) catch continue;
            source_allocated = true;
        }
        defer if (source_allocated) allocator.free(source_content);

        const target_content = core.fs_ops.readFile(allocator, target_path) catch {
            cli.printOut("--- {s} (source)\n+++ {s} (missing)\n", .{ file.target_rel, file.target_rel });
            found = true;
            continue;
        };
        defer allocator.free(target_content);

        if (!std.mem.eql(u8, source_content, target_content)) {
            cli.printOut("--- {s} (source)\n+++ {s} (target)\n", .{ file.target_rel, file.target_rel });
            // Simple line-by-line diff
            printSimpleDiff(source_content, target_content);
            found = true;
        }
    }

    if (!found) {
        if (filter_path) |fp| {
            cli.printOut("No differences for {s}.\n", .{fp});
        } else {
            cli.printOut("No differences.\n", .{});
        }
    }
}

fn printSimpleDiff(source: []const u8, target: []const u8) void {
    var src_it = std.mem.splitScalar(u8, source, '\n');
    var tgt_it = std.mem.splitScalar(u8, target, '\n');

    var line_num: usize = 1;
    while (true) {
        const src_line = src_it.next();
        const tgt_line = tgt_it.next();

        if (src_line == null and tgt_line == null) break;

        if (src_line != null and tgt_line != null) {
            if (!std.mem.eql(u8, src_line.?, tgt_line.?)) {
                cli.printOut("@@ line {d} @@\n", .{line_num});
                cli.printOut("-{s}\n", .{src_line.?});
                cli.printOut("+{s}\n", .{tgt_line.?});
            }
        } else if (src_line) |sl| {
            cli.printOut("-{s}\n", .{sl});
        } else if (tgt_line) |tl| {
            cli.printOut("+{s}\n", .{tl});
        }

        line_num += 1;
    }
}
