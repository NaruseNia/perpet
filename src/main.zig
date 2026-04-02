const std = @import("std");
const cli = @import("perpet").cli;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    const subcommand = args.next() orelse {
        cli.printUsage();
        return;
    };

    const cmd = cli.parseCommand(subcommand) orelse {
        cli.printErr("perpet: unknown command '{s}'\n", .{subcommand});
        cli.printErr("Run 'perpet --help' for usage.\n", .{});
        std.process.exit(1);
    };

    switch (cmd) {
        .init => try cli.init_cmd.run(&args),
        .add => try cli.add_cmd.run(&args),
        .apply => try cli.apply_cmd.run(&args),
        .remove => try cli.remove_cmd.run(&args),
        .diff => try cli.diff_cmd.run(&args),
        .status => try cli.status_cmd.run(&args),
        .edit => try cli.edit_cmd.run(&args),
        .list => try cli.list_cmd.run(&args),
        .update => try cli.update_cmd.run(&args),
        .cd => try cli.cd_cmd.run(&args),
        .git => try cli.git_cmd.run(&args),
        .config => try cli.config_cmd.run(&args),
        .help => cli.printUsage(),
        .version => cli.printVersion(),
    }
}

test {
    @import("std").testing.refAllDeclsRecursive(@import("perpet"));
}
