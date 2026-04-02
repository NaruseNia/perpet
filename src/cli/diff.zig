const std = @import("std");
const core = @import("../core/mod.zig");
const cli = @import("mod.zig");

pub fn run(args: *std.process.ArgIterator) !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const filter_path = args.next();

    var cfg = core.config.load(allocator) catch |err| {
        cli.printErr("error: failed to load config: {}\n", .{err});
        std.process.exit(1);
    };
    defer cfg.deinit();

    const files = core.manifest.enumerate(allocator, &cfg) catch |err| {
        cli.printErr("error: failed to read managed files: {}\n", .{err});
        std.process.exit(1);
    };
    defer core.manifest.freeFiles(allocator, files);

    var diff_count: usize = 0;
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
            cli.printOut("=== {s} ===\n", .{file.target_rel});
            cli.printOut("  (target file does not exist)\n\n", .{});
            diff_count += 1;
            continue;
        };
        defer allocator.free(target_content);

        if (!std.mem.eql(u8, source_content, target_content)) {
            cli.printOut("=== {s} ===\n", .{file.target_rel});
            printSimpleDiff(source_content, target_content);
            cli.printOut("\n", .{});
            diff_count += 1;
        }
    }

    if (diff_count == 0) {
        if (filter_path) |fp| {
            cli.printOut("No differences found for '{s}'.\n", .{fp});
        } else {
            cli.printOut("Everything is in sync.\n", .{});
        }
    } else {
        cli.printOut("{d} file{s} differ.\n", .{ diff_count, if (diff_count != 1) "s" else "" });
        cli.printOut("  hint: run 'perpet apply' to sync\n", .{});
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
                cli.printOut("  {d}: - {s}\n", .{ line_num, src_line.? });
                cli.printOut("  {d}: + {s}\n", .{ line_num, tgt_line.? });
            }
        } else if (src_line) |sl| {
            cli.printOut("  {d}: - {s}\n", .{ line_num, sl });
        } else if (tgt_line) |tl| {
            cli.printOut("  {d}: + {s}\n", .{ line_num, tl });
        }

        line_num += 1;
    }
}
