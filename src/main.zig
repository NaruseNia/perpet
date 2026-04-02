const std = @import("std");

pub fn main() !void {
    std.debug.print("perpet: dotfiles manager\n", .{});
}

test {
    @import("std").testing.refAllDeclsRecursive(@import("perpet"));
}
