const std = @import("std");

const Allocator = std.mem.Allocator;

const List = std.ArrayListUnmanaged;

pub fn MinHeapUnmanaged(comptime T: type) type {
    return HeapUnmanaged(T, (struct {
        fn before(a: T, b: T) bool {
            return a < b;
        }
    }).before);
}

pub fn MaxHeapUnmanaged(comptime T: type) type {
    return HeapUnmanaged(T, (struct {
        fn before(a: T, b: T) bool {
            return a > b;
        }
    }).before);
}

pub fn HeapUnmanaged(comptime T: type, comptime before: fn(T, T) bool) type {
    return struct {
        const Self = @This();

        items: List(T) = .{},

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.items.deinit(allocator);
        }

        fn swap(self: *Self, a: usize, b: usize) void {
            std.mem.swap(T, &self.items.items[a], &self.items.items[b]);
        }

        fn item(self: Self, i: usize) T {
            return self.items.items[i];
        }

        fn parent(i: usize) usize {
            return @divFloor(i - 1, 2);
        }

        fn up(self: *Self, i: usize) void {
            if (i > 0) {
                const p = parent(i);
                if (before(self.item(i), self.item(p))) {
                    self.swap(p, i);
                    self.up(p);
                }
            }
        }

        fn down(self: *Self, i: usize) void {
            const len = self.items.items.len;
            const ca_i = i * 2 + 1;
            if (ca_i < len) {
                const p = self.item(i);
                var best = .{ .i = i, .item = p };
                const child_a = self.item(ca_i);
                if (before(child_a, best.item)) {
                    best = .{ .i = ca_i, .item = child_a };
                }
                const cb_i = ca_i + 1;
                if (cb_i < len) {
                    const child_b = self.item(cb_i);
                    if (before(child_b, best.item)) {
                        best = .{ .i = cb_i, .item = child_b };
                    }
                }
                if (best.i != i) {
                    self.swap(i, best.i);
                    self.down(best.i);
                }
            }
        }

        pub fn push(self: *Self, allocator: Allocator, new: T) Allocator.Error!void {
            const len = self.items.items.len;
            try self.items.append(allocator, new);
            self.up(len);
        }

        pub fn pushAssumeCapacity(self: *Self, new: T,) void {
            const len = self.items.items.len;
            self.items.appendAssumeCapacity(new);
            self.up(len);
        }

        pub fn pop(self: *Self) ?T {
            return self.popAtIndex(0);
        }

        pub fn popAtIndex(self: *Self, i: usize) ?T {
            const len = self.items.items.len;
            if (i >= len) {
                return null;
            }
            const node = self.items.items[i];
            if (i == len - 1) {
                self.items.items.len -= 1;
                return node;
            }
            self.swap(i, len - 1);
            self.items.items.len -= 1;
            self.down(i);
            return node;
        }
    };
}