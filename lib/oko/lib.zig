const std = @import("std");

const File = std.fs.File;

const Allocator = std.mem.Allocator;

const history_len_max = 1024 * 16;

var history_start: usize = 0;
var history_end: usize = 0;

var history_head: ?*AllocHistory = null;

var is_running: std.atomic.Atomic(bool) = .{ .value = false };
var tick_thread: std.Thread = undefined;

pub fn start(comptime tick_time: comptime_float) !void {
    const S = struct {
        fn thread_main() void {
            while (is_running.load(.Monotonic)) {
                tick();
                std.time.sleep(comptime @intFromFloat(u64, tick_time * std.time.ns_per_s));
            }
        }
    };
    is_running.store(true, .Monotonic);
    tick_thread = try std.Thread.spawn(.{}, S.thread_main, .{});
}

pub fn stop() void {
    is_running.store(false, .Monotonic);
    tick_thread.join();
}

pub fn wrapAllocator(comptime tag: []const u8, allocator: Allocator) Allocator {
    return OkoAllocator(tag).init(allocator);
}

const AllocHistory = struct {
    history: [history_len_max]usize = undefined,
    tag: []const u8,
    next: ?*AllocHistory = null,
    size: usize = 0,
};

pub fn tick() void {
    defer {
        history_end += 1;
        history_end %= history_len_max;
        if (history_end == history_start) {
            history_start += 1;
            history_start %= history_len_max;
        }
    }
    var history_opt = history_head;
    while (history_opt) |history| {
        history_opt = history.next;
        history.history[history_end] = history.size;
    }
}

pub fn dumpAllocHistoryCsvFile(relative_path: []const u8) !void {
    var out = try std.fs.cwd().createFile(relative_path, .{
        .exclusive = false,
    });
    defer out.close();
    try dumpAllocHistoryCsv(out.writer());
}
pub fn dumpAllocHistoryCsv(writer: anytype) !void {
    var history_opt = history_head;
    while (history_opt) |history| {
        if (history_opt != history_head) {
            try writer.writeByte(',');
        }
        history_opt = history.next;
        try writer.print("\"{s}\"", .{history.tag});
    }
    try writer.writeByte('\n');
    var i: usize = history_start;
    while (i < history_end) : (i = (i + 1) % history_len_max) {
        history_opt = history_head;
        while (history_opt) |history| {
            if (history_opt != history_head) {
                try writer.writeByte(',');
            }
            history_opt = history.next;
            try writer.print("{d}", .{history.history[i]});
        }
        try writer.writeByte('\n');
    }
}

fn OkoAllocator(comptime tag: []const u8) type {
    return struct {
        var history: AllocHistory = .{
            .tag = tag,
        };

        var child: Allocator = undefined;

        var self = Self{};

        const Self = @This();

        const vtable: Allocator.VTable = .{
            .alloc = &alloc,
            .resize = &resize,
            .free = &free,
        };

        const allocator = Allocator{
            .ptr = undefined,
            .vtable = &vtable,
        };

        fn init(child_allocator: Allocator) Allocator {
            child = child_allocator;
            history.next = history_head;
            history_head = &history;
            return allocator;
        }
        /// Attempt to allocate exactly `len` bytes aligned to `1 << ptr_align`.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn alloc(_: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            log(@intCast(isize, len));
            return child.rawAlloc(len, ptr_align, ret_addr);
        }

        /// Attempt to expand or shrink memory in place. `buf.len` must equal the
        /// length requested from the most recent successful call to `alloc` or
        /// `resize`. `buf_align` must equal the same value that was passed as the
        /// `ptr_align` parameter to the original `alloc` call.
        ///
        /// A result of `true` indicates the resize was successful and the
        /// allocation now has the same address but a size of `new_len`. `false`
        /// indicates the resize could not be completed without moving the
        /// allocation to a different address.
        ///
        /// `new_len` must be greater than zero.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn resize(_: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            const delta: isize = @intCast(isize, new_len) - @intCast(isize, buf.len);
            log(delta);
            return child.rawResize(buf, buf_align, new_len, ret_addr);
        }

        /// Free and invalidate a buffer.
        ///
        /// `buf.len` must equal the most recent length returned by `alloc` or
        /// given to a successful `resize` call.
        ///
        /// `buf_align` must equal the same value that was passed as the
        /// `ptr_align` parameter to the original `alloc` call.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn free(_: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            const delta = -@intCast(isize, buf.len);
            log(delta);
            child.rawFree(buf, buf_align, ret_addr);
        }

        fn log(delta: isize) void {
            const new_size = @intCast(isize, history.size) + delta;
            history.size = @intCast(usize, if (new_size < 0) 0 else new_size);

            // if (out) |o| {
            //     out_mutex.lock();
            //     defer out_mutex.unlock();
            //     o.writer().print(tag ++ ",{d},{d}\n", .{delta, size}) catch unreachable;
            // }
        }
    };
}
