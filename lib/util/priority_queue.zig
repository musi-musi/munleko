const std = @import("std");

const Allocator = std.mem.Allocator;

const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const ResetEvent = std.Thread.ResetEvent;

pub fn JobQueueUnmanaged(comptime T: type) type {
    return struct {
        queue: Queue = .{},
        mutex: Mutex = .{},
        cond: Condition = .{},
        is_flushed: bool = false,

        pub const Queue = PriorityQueueUnmanaged(T);

        const Self = @This();

        /// push a new item to the queue
        /// if any threads are blocking on a call to `pop`, one will be woken up to recieve the item
        pub fn push(self: *Self, allocator: Allocator, item: T, priority: i32) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.queue.push(allocator, item, priority);
            self.cond.signal();
        }

        /// pop the next item from the queue
        /// if queue is empty, block until an item is available
        /// returns null when queue is flushed
        pub fn pop(self: *Self) ?Queue.Node {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (!self.is_flushed and self.queue.nodes.items.len == 0) {
                self.cond.wait(&self.mutex);
            }
            return self.queue.pop();
        }

        /// clear the queue, and broadcast to any threads blocking on `pop`
        /// any blocking `pop` calls on other threads will then return null
        pub fn flush(self: *Self, allocator: Allocator) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.is_flushed = true;
            self.queue.nodes.clearAndFree(allocator);
            self.cond.broadcast();
        }
    };
}

pub fn PriorityQueueUnmanaged(comptime T: type) type {
    return struct {
        nodes: Nodes = .{},

        pub const Node = struct {
            priority: i32,
            item: T,
        };

        pub const Nodes = std.ArrayListUnmanaged(Node);

        const Self = @This();

        fn swap(self: *Self, a: usize, b: usize) void {
            std.mem.swap(Node, &self.nodes.items[a], &self.nodes.items[b]);
        }

        fn priority(self: Self, i: usize) i32 {
            return self.nodes.items[i].priority;
        }

        fn parent(i: usize) usize {
            return @divFloor(i - 1, 2);
        }

        fn up(self: *Self, i: usize) void {
            if (i > 0) {
                const p = parent(i);
                if (self.priority(i) < self.priority(p)) {
                    self.swap(p, i);
                    self.up(p);
                }
            }
        }

        fn down(self: *Self, i: usize) void {
            const len = self.nodes.items.len;
            const ca = i * 2 + 1;
            if (ca < len) {
                const ip = self.priority(i);
                var best = .{ .i = i, .p = ip };
                const pa = self.priority(ca);
                if (pa < best.p) {
                    best = .{ .i = ca, .p = pa };
                }
                const cb = ca + 1;
                if (cb < len) {
                    const pb = self.priority(cb);
                    if (pb < best.p) {
                        best = .{ .i = cb, .p = pb };
                    }
                }
                if (best.i != i) {
                    self.swap(i, best.i);
                    self.down(best.i);
                }
            }
        }

        pub fn push(self: *Self, allocator: Allocator, item: T, p: i32) Allocator.Error!void {
            const len = self.nodes.items.len;
            try self.nodes.append(allocator, .{
                .priority = p,
                .item = item,
            });
            self.up(len);
        }

        pub fn pop(self: *Self) ?Node {
            const len = self.nodes.items.len;
            if (len > 0) {
                const node = self.nodes.items[0];
                if (len == 1) {
                    self.nodes.items.len = 0;
                    return node;
                } else {
                    self.swap(0, len - 1);
                    self.nodes.items.len -= 1;
                    self.down(0);
                    return node;
                }
            } else {
                return null;
            }
        }
    };
}
