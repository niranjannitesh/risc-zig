const std = @import("std");
const consts = @import("./constants.zig");
const Dram = @import("./dram.zig").Dram;
const ArrayList = std.ArrayList;

const MemoryMapError = error{IllegalAddressError};

pub const MemoryMap = struct {
    dram: Dram,

    const Self = @This();

    pub fn init(code: ArrayList(u8)) Self {
        return .{
            .dram = Dram.init(code),
        };
    }

    pub fn load(self: *Self, addr: u64, size: u64) !u64 {
        switch (addr) {
            consts.RAM_BASE_ADDR...consts.RAM_END_ADDR => return try self.dram.load(addr, size),
            else => return MemoryMapError.IllegalAddressError,
        }
    }
};
