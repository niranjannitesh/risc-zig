const std = @import("std");
const range = @import("./utils.zig").range;
const RAM_BASE_ADDR = @import("./constants.zig").RAM_BASE_ADDR;
const RAM_SIZE = @import("./constants.zig").RAM_SIZE;
const ArrayList = std.ArrayList;

const DramError = error{ InvalidSizeError, OutOfMemory };

pub const Dram = struct {
    buffer: []align(std.mem.page_size) u8,

    const Self = @This();

    pub fn init(code: []u8) !Self {
        var buffer = std.os.mmap(
            null,
            RAM_SIZE,
            std.os.PROT.READ | std.os.PROT.WRITE,
            std.os.MAP.PRIVATE | std.os.MAP.ANONYMOUS,
            -1,
            0,
        ) catch {
            return DramError.OutOfMemory;
        };
        for (code) |val, i| {
            buffer[i] = val;
        }
        return .{
            .buffer = buffer,
        };
    }

    pub fn load(self: *Self, addr: u64, size: u64) DramError!u64 {
        if (size != 8 and size != 16 and size != 32 and size != 64) {
            return DramError.InvalidSizeError;
        }

        const nbytes: u8 = @intCast(u8, size / 8);
        const buffer = self.buffer;
        const index: u64 = addr - RAM_BASE_ADDR;
        var value: u64 = @intCast(u64, buffer[index]);
        var i: u64 = 1;
        while (i < nbytes) : (i += 1) {
            value |= (@intCast(u64, buffer[index + i]) << @intCast(u6, i * 8));
        }
        return value;
    }

    pub fn store(self: *Self, addr: u64, size: u64, value: u64) !void {
        if (size != 8 and size != 16 and size != 32 and size != 64) {
            return DramError.InvalidSizeError;
        }
        const nbytes: u8 = @intCast(u8, size / 8);
        const buffer = self.buffer;
        const index: u64 = addr - RAM_BASE_ADDR;
        var i: u8 = 0;
        while (i < nbytes) : (i += 1) {
            buffer[index + i] = @intCast(u8, (value >> @intCast(u6, i * 8)) & 0xff);
        }
    }
};
