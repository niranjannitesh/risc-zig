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
        regs[2] = constants.RAM_BASE_ADDR + constants.RAM_SIZE;
        return .{
            .regs = regs,
            .pc = constants.RAM_BASE_ADDR,
            .mm = try MemoryMap.init(code),
        };
    }

    pub fn dump_regs(self: *Self) void {
        for (reg_name) |_, i| {
            std.debug.print("{s:04} = x{:<02}[{x:>18}]\t{s:04} = x{:<02}[{x:>18}]\t{s:04} = x{:<02}[{x:>18}]\t{s:04} = x{:<02}[{x:>18}]\n", .{ reg_name[i], i, self.regs[i], reg_name[i + 1], i + 1, self.regs[i + 1], reg_name[i + 2], i + 2, self.regs[i + 2], reg_name[i + 3], i + 3, self.regs[i + 3] });
            i += 3;
        }
    }

    pub fn fetch(self: *Self) !u64 {
        return try self.mm.load(self.pc, 32);
    }

    pub fn execute(self: *Self, inst: u64) !u64 {
        const opcode = inst & 0x0000007f;
        const rd = (inst & 0x00000f80) >> 7;
        const rs1 = (inst & 0x000f8000) >> 15;
        const rs2 = (inst & 0x01f00000) >> 20;
        const funct3 = (inst & 0x00007000) >> 12;
        const funct7 = (inst & 0xfe000000) >> 25;

        self.regs[0] = 0;

        switch (opcode) {
            0x03 => {
                const imm = @bitCast(u64, @intCast(i64, @bitCast(i32, @truncate(u32, inst & 0xfff00000)) >> 20));
                const addr = self.regs[rs1] +% imm;
                switch (funct3) {
                    0x0 => {
                        // LB
                        const data = try self.mm.load(addr, 8);
                        self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i8, data)));
                        return self.pc + 4;
                    },
                    0x1 => {
                        // LH
                        const data = try self.mm.load(addr, 16);
                        self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i16, data)));
                        return self.pc + 4;
                    },
                    0x2 => {
                        // LW
                        const data = try self.mm.load(addr, 32);
                        self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, data)));
                        return self.pc + 4;
                    },
                    0x3 => {
                        // LD
                        self.regs[rd] = try self.mm.load(addr, 64);
                        return self.pc + 4;
                    },
                    0x4 => {
                        // LBU
                        const data = try self.mm.load(addr, 8);
                        self.regs[rd] = data;
                        return self.pc + 4;
                    },
                    0x5 => {
                        // LHU
                        const data = try self.mm.load(addr, 16);
                        self.regs[rd] = data;
                        return self.pc + 4;
                    },
                    0x6 => {
                        // LWU
                        const data = try self.mm.load(addr, 32);
                        self.regs[rd] = data;
                        return self.pc + 4;
                    },
                    else => {
                        return CPUError.InvalidInstructionError;
                    },
                }
            },
            0x13 => {
                const imm: u64 = @bitCast(u64, @intCast(i64, @bitCast(i32, @truncate(u32, inst & 0xfff00000))) >> 20);
                const shamt = @truncate(u32, imm & 0x1f);
                switch (funct3) {
                    0x0 => {
                        // ADDI
                        self.regs[rd] = self.regs[rs1] +% imm;
                        return self.pc + 4;
                    },
                    0x1 => {
                        // SLLI
                        self.regs[rd] = self.regs[rs1] << @intCast(u6, shamt);
                        return self.pc + 4;
                    },
                    0x2 => {
                        // SLTI
                        self.regs[rd] = @boolToInt(@intCast(i64, self.regs[rs1]) < imm);
                        return self.pc + 4;
                    },
                    0x3 => {
                        // SLTIU
                        self.regs[rd] = @boolToInt(self.regs[rs1] < imm);
                        return self.pc + 4;
                    },
                    0x4 => {
                        // XORI
                        self.regs[rd] = self.regs[rs1] ^ imm;
                        return self.pc + 4;
                    },
                    0x5 => {
                        switch (funct7) {
                            0x0 => {
                                // SRLI
                                self.regs[rd] = self.regs[rs1] >> @intCast(u6, shamt);
                                return self.pc + 4;
                            },
                            0x20 => {
                                // SRAI
                                self.regs[rd] = @bitCast(u64, @bitCast(i64, self.regs[rs1]) >> @truncate(u6, shamt));
                                return self.pc + 4;
                            },
                            else => {
                                return CPUError.InvalidInstructionError;
                            },
                        }
                    },
                    0x6 => {
                        // ORI
                        self.regs[rd] = self.regs[rs1] | imm;
                        return self.pc + 4;
                    },
                    0x7 => {
                        // ANDI
                        self.regs[rd] = self.regs[rs1] & imm;
                        return self.pc + 4;
                    },
                    else => {
                        return CPUError.InvalidInstructionError;
                    },
                }
            },
            0x17 => {
                const imm: u64 = @bitCast(u64, @intCast(i64, @bitCast(i32, @truncate(u32, inst & 0xfffff000))));
                self.regs[rd] = self.pc +% imm;
                return self.pc + 4;
            },
            0x1b => {
                const imm = @bitCast(u64, @intCast(i64, @bitCast(i32, @truncate(u32, inst & 0xfff00000))) >> 20);
                const shamt = @intCast(u32, imm & 0x1f);
                switch (funct3) {
                    0x0 => {
                        // ADDIW
                        self.regs[rd] = @bitCast(u64, @intCast(i64, @truncate(u32, self.regs[rs1] +% imm)));
                        return self.pc + 4;
                    },
                    0x1 => {
                        // SLLIW
                        self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, self.regs[rs1])) << @intCast(u6, shamt));
                        return self.pc + 4;
                    },
                    0x5 => {
                        switch (funct7) {
                            0x0 => {
                                // SRLIW
                                self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, @intCast(u32, self.regs[rs1]) >> @intCast(u5, shamt))));
                                return self.pc + 4;
                            },
                            0x20 => {
                                // SRAIW
                                self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, self.regs[rs1])) >> @intCast(u6, shamt));
                                return self.pc + 4;
                            },
                            else => {
                                return CPUError.InvalidInstructionError;
                            },
                        }
                    },
                    else => {
                        return CPUError.InvalidInstructionError;
                    },
                }
            },
            0x23 => {
                const imm: u64 = @bitCast(u64, @intCast(i64, @bitCast(i32, @truncate(u32, inst & 0xfe000000))) >> 20) | ((inst >> 7) & 0x1f);
                const addr = self.regs[rs1] +% imm;
                switch (funct3) {
                    0x0 => {
                        // SB
                        try self.mm.store(addr, 8, self.regs[rs1] & 0xff);
                        return self.pc + 4;
                    },
                    0x1 => {
                        // SH
                        try self.mm.store(addr, 16, self.regs[rs1] & 0xffff);
                        return self.pc + 4;
                    },
                    0x2 => {
                        // SW
                        try self.mm.store(addr, 32, self.regs[rs2]);
                        return self.pc + 4;
                    },
                    0x3 => {
                        // SD
                        try self.mm.store(addr, 64, self.regs[rs2]);
                        return self.pc + 4;
                    },
                    else => {
                        return CPUError.InvalidInstructionError;
                    },
                }
            },
            0x33 => {
                const shamt = @intCast(u32, self.regs[rs2] & 0x1f);
                switch (funct3) {
                    0x0 => {
                        switch (funct7) {
                            0x0 => {
                                // ADD
                                self.regs[rd] = self.regs[rs1] +% self.regs[rs2];
                                return self.pc + 4;
                            },
                            0x20 => {
                                // SUB
                                self.regs[rd] = self.regs[rs1] -% self.regs[rs2];
                                return self.pc + 4;
                            },
                            else => {
                                return CPUError.InvalidInstructionError;
                            },
                        }
                    },
                    0x1 => {
                        // SLL
                        self.regs[rd] = self.regs[rs1] << @intCast(u6, shamt);
                        return self.pc + 4;
                    },
                    0x2 => {
                        // SLT
                        self.regs[rd] = @boolToInt(@intCast(i64, self.regs[rs1]) < @intCast(i64, self.regs[rs2]));
                        return self.pc + 4;
                    },
                    0x3 => {
                        // SLTU
                        self.regs[rd] = @boolToInt(self.regs[rs1] < self.regs[rs2]);
                        return self.pc + 4;
                    },
                    0x4 => {
                        // XOR
                        self.regs[rd] = self.regs[rs1] ^ self.regs[rs2];
                        return self.pc + 4;
                    },
                    0x5 => {
                        switch (funct7) {
                            0x0 => {
                                // SRL
                                self.regs[rd] = self.regs[rs1] >> @intCast(u6, shamt);
                                return self.pc + 4;
                            },
                            0x20 => {
                                // SRA
                                self.regs[rd] = @bitCast(u64, @bitCast(i64, self.regs[rs1]) >> @truncate(u6, shamt));
                                return self.pc + 4;
                            },
                            else => {
                                return CPUError.InvalidInstructionError;
                            },
                        }
                    },
                    0x6 => {
                        // OR
                        self.regs[rd] = self.regs[rs1] | self.regs[rs2];
                        return self.pc + 4;
                    },
                    0x7 => {
                        // AND
                        self.regs[rd] = self.regs[rs1] & self.regs[rs2];
                        return self.pc + 4;
                    },
                    else => {
                        return CPUError.InvalidInstructionError;
                    },
                }
            },
            0x37 => {
                // LUI
                self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, inst & 0xfffff000)));
                return self.pc + 4;
            },
            0x3b => {
                const shamt = @intCast(u32, self.regs[rs2] & 0x1f);
                switch (funct3) {
                    0x0 => {
                        switch (funct7) {
                            0x0 => {
                                // ADDW
                                self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, self.regs[rs1])) +% @intCast(i32, self.regs[rs2]));
                                return self.pc + 4;
                            },
                            0x20 => {
                                // SUBW
                                self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, self.regs[rs1])) -% @intCast(i32, self.regs[rs2]));
                                return self.pc + 4;
                            },
                            else => {
                                return CPUError.InvalidInstructionError;
                            },
                        }
                    },
                    0x1 => {
                        // SLLW
                        self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, self.regs[rs1])) << @intCast(u6, shamt));
                        return self.pc + 4;
                    },
                    0x5 => {
                        switch (funct7) {
                            0x0 => {
                                // SRLW
                                self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, @intCast(u32, self.regs[rs1]) >> @intCast(u5, shamt))));
                                return self.pc + 4;
                            },
                            0x20 => {
                                // SRAW
                                self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, self.regs[rs1])) >> @intCast(u5, shamt));
                                return self.pc + 4;
                            },
                            else => {
                                return CPUError.InvalidInstructionError;
                            },
                        }
                    },
                    else => {
                        return CPUError.InvalidInstructionError;
                    },
                }
            },
            0x63 => {
                const imm = @bitCast(u64, @intCast(i64, @bitCast(i32, @truncate(u32, inst & 0xfe000000)) >> 20)) | ((inst & 0x80) << 4) | ((inst >> 20) & 0x7e0) | ((inst >> 7) & 0x1e);
                switch (funct3) {
                    0x0 => {
                        // BEQ
                        if (self.regs[rs1] == self.regs[rs2]) {
                            return self.pc +% imm;
                        }
                        return self.pc + 4;
                    },
                    0x1 => {
                        // BNE
                        if (self.regs[rs1] != self.regs[rs2]) {
                            return self.pc +% imm;
                        }
                        return self.pc + 4;
                    },
                    0x4 => {
                        // BLT
                        if (@intCast(i64, self.regs[rs1]) < @intCast(i64, self.regs[rs2])) {
                            return self.pc +% imm;
                        }
                        return self.pc + 4;
                    },
                    0x5 => {
                        // BGE
                        if (@intCast(i64, self.regs[rs1]) >= @intCast(i64, self.regs[rs2])) {
                            return self.pc +% imm;
                        }
                        return self.pc + 4;
                    },
                    0x6 => {
                        // BLTU
                        if (self.regs[rs1] < self.regs[rs2]) {
                            return self.pc +% imm;
                        }
                        return self.pc + 4;
                    },
                    0x7 => {
                        // BGEU
                        if (self.regs[rs1] >= self.regs[rs2]) {
                            return self.pc +% imm;
                        }
                        return self.pc + 4;
                    },
                    else => {
                        return CPUError.InvalidInstructionError;
                    },
                }
            },
            0x67 => {
                // JALR
                const imm = @bitCast(u64, @intCast(i64, @bitCast(i32, @truncate(u32, inst & 0xfff00000))) >> 20);
                self.regs[rd] = self.pc + 4;
                return (self.regs[rs1] +% imm) & ~@intCast(u64, 1);
            },
            0x6f => {
                // JAL
                const imm = @bitCast(u64, @intCast(i64, @bitCast(i32, @truncate(u32, inst & 0x80000000))) >> 11) | (inst & 0xff000) | ((inst >> 9) & 0x800) | ((inst >> 20) & 0x7fe);
                self.regs[rd] = self.pc + 4;
                return self.pc +% imm;
            },
            else => {
                return CPUError.InvalidInstructionError;
            },
        }
    }
};
