const std = @import("std");
const ArrayList = std.ArrayList;

/// 128MB of DRAM
pub const DRAM_SIZE: u64 = 1024 * 1024 * 128;

const abi = [_][]const u8{
    "zero", " ra ", " sp ", " gp ", " tp ", " t0 ", " t1 ", " t2 ", " s0 ", " s1 ", " a0 ",
    " a1 ", " a2 ", " a3 ", " a4 ", " a5 ", " a6 ", " a7 ", " s2 ", " s3 ", " s4 ", " s5 ",
    " s6 ", " s7 ", " s8 ", " s9 ", " s10", " s11", " t3 ", " t4 ", " t5 ", " t6 ",
};

pub const CPU = struct {
    regs: [32]u64,
    pc: u64,
    dram: ArrayList(u8),

    const Self = @This();

    pub fn init(code: ArrayList(u8)) Self {
        var regs = [_]u64{0} ** 32;
        regs[2] = DRAM_SIZE;
        return .{
            .regs = regs,
            .pc = 0,
            .dram = code,
        };
    }

    pub fn dump_regs(self: *Self) void {
        for (abi) |_, i| {
            std.debug.print("{s} = x{:02}[0x{x:<.18}] \t {s} = x{:02}[0x{x:<.18}] \t {s} = x{:02}[0x{x:<.18}] \t {s} = x{:02}[0x{x:<.18}]\n", .{ abi[i], i, self.regs[i], abi[i + 1], i + 1, self.regs[i + 1], abi[i + 2], i + 2, self.regs[i + 2], abi[i + 3], i + 3, self.regs[i + 3] });
            i += 3;
        }
    }

    /// in riscv one instruction is 32bit
    /// so we fetch 4 bytes at a time
    /// [pc, pc+1, pc+2, pc+3] with little-endian
    pub fn fetch(self: *Self) u32 {
        const index = self.pc;
        const buffer = self.dram.items;
        self.pc += 4;
        return @intCast(u32, buffer[index]) | (@intCast(u32, buffer[index + 1]) << 8) | (@intCast(u32, buffer[index + 2]) << 16) | (@intCast(u32, buffer[index + 3]) << 24);
    }

    pub fn execute(self: *Self, inst: u32) void {
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
            },
            // ADD
            0x33 => {
                self.regs[rd] = self.regs[rs1] +% self.regs[rs2];
            },
            else => {
                std.debug.print("Unknown opcode: 0x{x}\n", .{opcode});
            },
        }
    }
};
