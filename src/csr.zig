const std = @import("std");
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

    pub fn load(self: *Self, addr: usize) u64 {
        switch (addr) {
            constants.SIE => return self.csrs[constants.MIE] & self.csrs[constants.MIDELEG],
            constants.SIP => return self.csrs[constants.MIP] & self.csrs[constants.MIDELEG],
            constants.SSTATUS => return self.csrs[constants.MSTATUS] & constants.MASK_SSTATUS,
            else => return self.csrs[addr],
        }
    }

    pub fn store(self: *Self, addr: usize, value: u64) void {
        switch (addr) {
            constants.SIE => self.csrs[constants.MIE] = (self.csrs[constants.MIE] & (~self.csrs[constants.MIDELEG])) | (value & self.csrs[constants.MIDELEG]),
            constants.SIP => self.csrs[constants.MIP] = (self.csrs[constants.MIE] & (~self.csrs[constants.MIDELEG])) | (value & self.csrs[constants.MIDELEG]),
            constants.SSTATUS => self.csrs[constants.MSTATUS] = (self.csrs[constants.MSTATUS] & (~constants.MASK_SSTATUS)) | (value & constants.MASK_SSTATUS),
            else => self.csrs[addr] = value,
        }
    }
};
