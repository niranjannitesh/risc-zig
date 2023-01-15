const std = @import("std");
const CPU = @import("./cpu.zig").CPU;
const RAM_SIZE = @import("./constants.zig").RAM_SIZE;
const ArrayList = std.ArrayList;

const allocator = std.heap.page_allocator;

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    if (args.len != 2) {
        std.debug.print("Usage: x <file>\n", .{});
        return;
    }
    const buffer = try std.fs.cwd().readFileAlloc(allocator, args[1], std.math.maxInt(usize));
    var cpu = try CPU.init(buffer);
    while (true) {
        const inst = cpu.fetch() catch |err| {
            std.debug.print("{}\n", .{err});
            break;
        };
        const pc = cpu.execute(inst) catch |err| {
            std.debug.print("{}\n", .{err});
            break;
        };
        cpu.pc = pc;
    }
    cpu.dump_regs();
}
