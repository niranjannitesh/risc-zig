const constants = @import("./constants.zig");

pub const CSR = struct {
    csrs: [constants.CSR_COUNT]u64,

    const Self = @This();

    pub fn init() Self {
        var csrs = [_]u64{0} ** NUM_CSRS;
        return .{
            .csrs = csrs,
        };
    }
};
