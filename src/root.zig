pub const core = @import("core/mod.zig");
pub const cli = @import("cli/mod.zig");

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
