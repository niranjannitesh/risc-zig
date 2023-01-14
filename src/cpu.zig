const std = @import("std");
const constants = @import("./constants.zig");
const MemoryMap = @import("./memory-map.zig").MemoryMap;
const ArrayList = std.ArrayList;

const CPUError = error{InvalidInstructionError};

const reg_name = [_][]const u8{
    "zero", "ra", "sp", "gp", "tp",  "t0",  "t1", "t2", "s0", "s1", "a0",
    "a1",   "a2", "a3", "a4", "a5",  "a6",  "a7", "s2", "s3", "s4", "s5",
    "s6",   "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
};

pub const CPU = struct {
    regs: [32]u64,
    pc: u64,
    mm: MemoryMap,

    const Self = @This();

    pub fn init(code: []u8) !Self {
        var regs = [_]u64{0} ** 32;
        regs[2] = constants.RAM_SIZE;
        return .{
            .regs = regs,
            .pc = constants.RAM_BASE_ADDR,
            .mm = try MemoryMap.init(code),
        };
    }

    pub fn dump_regs(self: *Self) void {
        for (reg_name) |_, i| {
            std.debug.print("{s:04} = x{:<02}[0x{x:<.18}] \t {s:04} = x{:<02}[0x{x:<.18}] \t {s:04} = x{:<02}[0x{x:<.18}] \t {s:04} = x{:<02}[0x{x:<.18}]\n", .{ reg_name[i], i, self.regs[i], reg_name[i + 1], i + 1, self.regs[i + 1], reg_name[i + 2], i + 2, self.regs[i + 2], reg_name[i + 3], i + 3, self.regs[i + 3] });
            i += 3;
        }
    }

    pub fn fetch(self: *Self) !u64 {
        return try self.mm.load(self.pc, 32);
    }

    pub fn execute(self: *Self, inst: u64) !void {
        const opcode = inst & 0b1111111;
        // move 7 bits to the right and take the first 5 bits
        const rd = (inst >> 7) & 0b11111;
        // move 15 bits to the right and take the first 5 bits
        const rs1 = (inst >> 15) & 0b11111;
        // move 20 bits to the right and take the first 5 bits
        const rs2 = (inst >> 20) & 0b11111;

        // Emulate that register x0 is hardwired with all bits equal to 0.
        self.regs[0] = 0;

        switch (opcode) {
            // ADDI
            0x13 => {
                // move to 32 bit and get til 20 bits from the right
                // which is 12 bits
                const imm = @intCast(u64, @intCast(i64, @intCast(i32, inst & 0xfff00000) >> 20));
                self.regs[rd] = self.regs[rs1] +% imm;
                self.pc += 4;
            },
            // ADD
            0x33 => {
                self.regs[rd] = self.regs[rs1] +% self.regs[rs2];
                self.pc += 4;
            },
            else => {
                return CPUError.InvalidInstructionError;
            },
        }
    }
};
