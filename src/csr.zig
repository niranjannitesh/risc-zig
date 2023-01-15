const constants = @import("./constants.zig");

pub const CSR = struct {
    csrs: [constants.NUM_CSRS]u64,

    const Self = @This();

    pub fn init() Self {
        var csrs = [_]u64{0} ** constants.NUM_CSRS;
        return .{
            .csrs = csrs,
        };
    }
};
