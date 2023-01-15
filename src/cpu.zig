const std = @import("std");
const constants = @import("./constants.zig");
const MemoryMap = @import("./memory-map.zig").MemoryMap;
const CSR = @import("./csr.zig").CSR;
const ArrayList = std.ArrayList;

const CPUError = error{InvalidInstructionError};

const reg_name = [_][]const u8{
    "zero", "ra", "sp", "gp", "tp",  "t0",  "t1", "t2", "s0", "s1", "a0",
    "a1",   "a2", "a3", "a4", "a5",  "a6",  "a7", "s2", "s3", "s4", "s5",
    "s6",   "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
};

const Mode = enum(u64) {
    Machine = 0b11,
    Supervisor = 0b01,
    User = 0b00,
};

pub const CPU = struct {
    regs: [32]u64,
    pc: u64,
    mm: MemoryMap,
    csr: CSR,
    mode: Mode = .Machine,

    const Self = @This();

    pub fn init(code: []u8) !Self {
        var regs = [_]u64{0} ** 32;
        regs[2] = constants.RAM_BASE_ADDR + constants.RAM_SIZE;
        return .{
            .regs = regs,
            .pc = constants.RAM_BASE_ADDR,
            .mm = try MemoryMap.init(code),
            .csr = CSR.init(),
        };
    }

    pub fn dump_regs(self: *Self) void {
        for (reg_name) |_, i| {
            std.debug.print("{s:04} = x{:<02}[{x:>18}]\t{s:04} = x{:<02}[{x:>18}]\t{s:04} = x{:<02}[{x:>18}]\t{s:04} = x{:<02}[{x:>18}]\n", .{ reg_name[i], i, self.regs[i], reg_name[i + 1], i + 1, self.regs[i + 1], reg_name[i + 2], i + 2, self.regs[i + 2], reg_name[i + 3], i + 3, self.regs[i + 3] });
            i += 3;
        }
        std.debug.print("\n\n{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\n{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\n{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\n{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\n{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\n{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\n", .{
            "pc",         self.pc,
            "mhartid",    self.csr.load(constants.MHARTID),
            "mstatus",    self.csr.load(constants.MSTATUS),
            "mtvec",      self.csr.load(constants.MTVEC),
            "mepc",       self.csr.load(constants.MEPC),
            "mcause",     self.csr.load(constants.MCAUSE),
            "mtval",      self.csr.load(constants.MTVAL),
            "medeleg",    self.csr.load(constants.MEDELEG),
            "mscratch",   self.csr.load(constants.MSCRATCH),
            "MIP",        self.csr.load(constants.MIP),
            "mcounteren", self.csr.load(constants.MCOUNTEREN),
            "sstatus",    self.csr.load(constants.SSTATUS),
            "stvec",      self.csr.load(constants.STVEC),
            "sepc",       self.csr.load(constants.SEPC),
            "scause",     self.csr.load(constants.SCAUSE),
            "stval",      self.csr.load(constants.STVAL),
        });
        std.debug.print("{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\t{s:>10}=[{x:>18}]\n", .{ "sscratch", self.csr.load(constants.SSCRATCH), "sip", self.csr.load(constants.SIP), "satp", self.csr.load(constants.SATP) });
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
            0x0f => {
                switch (funct3) {
                    0x0 => {
                        // fence
                        return self.update_pc();
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
            0x2f => {
                // RV64A: "A" standard extension for atomic instructions
                const funct5 = (funct7 & 0b1111100) >> 2;
                switch (funct3) {
                    0x2 => {
                        switch (funct5) {
                            0x0 => {
                                // AMOADD.W
                                const t = try self.mm.load(self.regs[rs1], 32);
                                try self.mm.store(self.regs[rs1], 32, t +% self.regs[rs2]);
                                self.regs[rd] = t;
                                return self.pc + 4;
                            },
                            0x1 => {
                                //AMOSWAP.W
                                const t = try self.mm.load(self.regs[rs1], 32);
                                try self.mm.store(self.regs[rs1], 32, self.regs[rs2]);
                                self.regs[rd] = t;
                                return self.pc + 4;
                            },
                        }
                    },
                    0x3 => {
                        switch (funct5) {
                            0x0 => {
                                // AMOADD.D
                                const t = try self.mm.load(self.regs[rs1], 64);
                                try self.mm.store(self.regs[rs1], 64, t +% self.regs[rs2]);
                                self.regs[rd] = t;
                                return self.pc + 4;
                            },
                            0x1 => {
                                // AMOSWAP.D
                                const t = try self.mm.load(self.regs[rs1], 64);
                                try self.mm.store(self.regs[rs1], 64, self.regs[rs2]);
                                self.regs[rd] = t;
                                return self.pc + 4;
                            },
                        }
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
                            0x1 => {
                                // mul
                                self.regs[rd] = self.regs[rs1] *% self.regs[rs2];
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
                            0x1 => {
                                // divu
                                // @todo: check for divide by 0
                                self.regs[rd] = @intCast(u64, @intCast(u32, self.regs[rs1]) / @intCast(u32, self.regs[rs2]));
                                return self.pc + 4;
                            },
                            0x20 => {
                                // sraw
                                self.regs[rd] = @intCast(u64, @intCast(i64, @intCast(i32, self.regs[rs1])) >> @intCast(u5, shamt));
                                return self.pc + 4;
                            },
                            else => {
                                return CPUError.InvalidInstructionError;
                            },
                        }
                    },
                    0x7 => {
                        switch (funct7) {
                            0x1 => {
                                // remuw
                                self.regs[rd] = @intCast(u64, @intCast(u32, self.regs[rs1]) % @intCast(u32, self.regs[rs2]));
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
            0x73 => {
                const addr = @as(usize, (inst & 0xfff00000) >> 20);
                switch (funct3) {
                    0x0 => {
                        switch (funct7) {
                            0x8 => {
                                switch (rs2) {
                                    0x2 => {
                                        // sret
                                        var sstatus = self.csr.load(constants.SSTATUS);
                                        self.mode = @intToEnum(Mode, (sstatus & constants.MASK_SPP) >> 8);
                                        const spie = (sstatus & constants.MASK_SPIE) >> 5;
                                        sstatus = (sstatus & ~constants.MASK_SIE) | (spie << 1);
                                        sstatus |= constants.MASK_SPIE;
                                        sstatus &= ~constants.MASK_SPP;
                                        self.csr.store(constants.SSTATUS, sstatus);
                                        return self.csr.load(constants.SEPC) & ~@intCast(u64, 0b11);
                                    },
                                    else => {
                                        return CPUError.InvalidInstructionError;
                                    },
                                }
                            },
                            0x9 => {
                                // sfence.vma
                                return self.pc + 4;
                            },
                            0x18 => {
                                switch (rs2) {
                                    0x2 => {
                                        // mret
                                        var mstatus = self.csr.load(constants.MSTATUS);
                                        self.mode = @intToEnum(Mode, (mstatus & constants.MASK_MPP) >> 11);
                                        const mpie = (mstatus & constants.MASK_MPIE) >> 7;
                                        mstatus = (mstatus & ~constants.MASK_MIE) | (mpie << 3);
                                        mstatus |= constants.MASK_MPIE;
                                        mstatus &= ~constants.MASK_MPP;
                                        mstatus &= ~constants.MASK_MPRV;
                                        self.csr.store(constants.MSTATUS, mstatus);
                                        return self.csr.load(constants.MEPC) & ~@intCast(u64, 0b11);
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
                    0x1 => {
                        // csrrw
                        const t = self.csr.load(addr);
                        self.csr.store(addr, self.regs[rs1]);
                        self.regs[rd] = t;
                        return self.pc + 4;
                    },
                    0x2 => {
                        // csrrs
                        const v = self.csr.load(addr);
                        self.csr.store(addr, v | self.regs[rs1]);
                        self.regs[rd] = v;
                        return self.pc + 4;
                    },
                    0x3 => {
                        // csrrc
                        const v = self.csr.load(addr);
                        self.csr.store(addr, v & (~self.regs[rs1]));
                        self.regs[rd] = v;
                        return self.pc + 4;
                    },
                    0x5 => {
                        // csrrwi
                        self.regs[rd] = self.csr.load(addr);
                        self.csr.store(addr, rs1);
                        return self.pc + 4;
                    },
                    0x6 => {
                        // csrrsi
                        const zimm = @intCast(u64, rs1);
                        const v = self.csr.load(addr);
                        self.regs[rd] = v;
                        self.csr.store(addr, v | zimm);
                        return self.pc + 4;
                    },
                    0x7 => {
                        // csrrci
                        const zimm = @intCast(u64, rs1);
                        const v = self.csr.load(addr);
                        self.regs[rd] = v;
                        self.csr.store(addr, v & (~zimm));
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
    }
};
