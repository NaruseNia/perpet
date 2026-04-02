pub const core = @import("core/mod.zig");

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
