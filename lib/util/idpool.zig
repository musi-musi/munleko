const std = @import("std");

const Allocator = std.mem.Allocator;

const heap = @import("heap.zig");

pub fn IdPool(comptime Id_: type) type {
    return struct {
        const Self = @This();

        pool: IdPoolUnmanaged(Id) = .{},
        allocator: Allocator,

        pub const Id = Id_;

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.pool.deinit(self.allocator);
        }

        pub fn acquire(self: *Self) Allocator.Error!Id {
            return self.pool.acquire(self.allocator);
        }

        pub fn release(self: *Self, id: Id) void {
            self.pool.release(id);
        }
    };
}

pub fn IdPoolUnmanaged(comptime Id_: type) type {
    return struct {
        const Self = @This();

        unused: heap.MinHeapUnmanaged(Id) = .{},
        capacity: usize = 0,

        pub const Id = Id_;

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.unused.deinit(allocator);
        }

        pub fn acquire(self: *Self, allocator: Allocator) Allocator.Error!Id {
            if (self.unused.pop()) |id| {
                return id;
            } else {
                const id = @as(Id, @intCast(self.capacity));
                self.capacity += 1;
                try self.unused.items.ensureTotalCapacity(allocator, self.capacity);
                return id;
            }
        }

        pub fn release(self: *Self, id: Id) void {
            self.unused.pushAssumeCapacity(id);
        }
    };
}
