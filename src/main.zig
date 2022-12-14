const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const DRAM_SIZE = @import("cpu.zig").DRAM_SIZE;
const ArrayList = std.ArrayList;

const allocator = std.heap.page_allocator;

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.c_allocator);
    if (args.len != 2) {
        std.debug.print("Usage: x <file>\n", .{});
        return;
    }
    const buffer = try std.fs.cwd().readFileAlloc(allocator, args[1], std.math.maxInt(usize));
    var code = try ArrayList(u8).initCapacity(allocator, DRAM_SIZE);
    try code.appendSlice(buffer[0..]);
    var cpu = CPU.init(code);
    while (cpu.pc < cpu.dram.items.len) {
        const inst = cpu.fetch();
        cpu.execute(inst);
    }
    cpu.dump_regs();
}
