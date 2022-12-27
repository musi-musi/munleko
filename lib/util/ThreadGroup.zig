const std = @import("std");

const Allocator = std.mem.Allocator;
const Thread = std.Thread;

const ThreadGroup = @This();

allocator: Allocator,
threads: []Thread,

pub fn countFromCpuCount(factor: f32) usize {
    const count =  @floatToInt(usize, @floor(@intToFloat(f32, Thread.getCpuCount() catch 1) * factor));
    if (count == 0) return 1;
    return count;
}

pub fn spawnCpuCount(allocator: Allocator, cpu_factor: f32, config: Thread.SpawnConfig, comptime function: anytype, args: anytype) !ThreadGroup {
    return try spawn(allocator, countFromCpuCount(cpu_factor), config, function, args);
}

pub fn spawn(allocator: Allocator, count: usize, config: Thread.SpawnConfig, comptime function: anytype, args: anytype) !ThreadGroup {
    const threads = try allocator.alloc(Thread, count);
    errdefer allocator.free(threads);
    for (threads) |*thread| {
        thread.* = try Thread.spawn(config, function, args);
    }
    return ThreadGroup {
        .allocator = allocator,
        .threads = threads,
    };
}

pub fn join(self: *ThreadGroup) void {
    const allocator = self.allocator;
    defer allocator.free(self.threads);
    for (self.threads) |thread| {
        thread.join();
    }
}
