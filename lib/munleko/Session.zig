const std = @import("std");

const Allocator = std.mem.Allocator;
const Thread = std.Thread;


const time = std.time;
const Timer = time.Timer;
const Self = @This();


allocator: Allocator,
thread: ?Thread = null,
is_running: bool = false,
callbacks: Callbacks,

timer: Timer = undefined,
tick_count: u64 = 0,

tick_rate: f32 = 40,


pub fn init(allocator: Allocator, callbacks: Callbacks) !Self {
    return Self {
        .allocator = allocator,
        .callbacks = callbacks,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn start(self: *Self) !void {
    if (self.thread == null) {
        self.timer = try Timer.start();
        self.tick_count = 0;
        self.is_running = true;
        self.thread = try Thread.spawn(.{}, run, .{self});
    }
}

pub fn stop(self: *Self) void {
    if (self.thread) |thread| {
        self.is_running = false;
        thread.join();
    }
}

/// session main loop
/// this is the session thread main
pub fn run(self: *Self) !void {
    while (self.is_running) : (self.nextTick()) {
        try self.callbacks.tick(self);
    }
}

fn nextTick(self: *Self) void {
    const elapsed = self.timer.read();
    const quota = self.nsPerTick();
    if (elapsed < quota) {
        time.sleep(quota - elapsed);
    }
    else {
        const extra = elapsed - quota; 
        const elapsed_ms = @divFloor(elapsed, time.ns_per_ms);
        const extra_ms = @divFloor(extra, time.ns_per_ms);
        std.log.warn("tick {d} took {d}ms too long ({d}ms total)", .{self.tick_count, extra_ms, elapsed_ms});
    }
    self.tick_count += 1;
    self.timer.reset();
}

pub fn nsPerTick(self: Self) u64 {
    return @floatToInt(u64, 1_000_000_000 / self.tick_rate);
}

pub const Callbacks = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        tick: *const fn(ptr: *anyopaque, session: *Self) anyerror!void,
    };

    pub fn init(
        pointer: anytype,
        comptime tickFn: *const fn(@TypeOf(pointer), *Self) anyerror!void,
    ) Callbacks {
        const Ptr = @TypeOf(pointer);
        const alignment = @typeInfo(Ptr).Pointer.alignment;

        return .{
            .ptr = pointer,
            .vtable = &(struct {
                const vtable = VTable {
                    .tick = tickImpl,
                };

                fn tickImpl(ptr: *anyopaque, session: *Self) anyerror!void {
                    const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                    try @call(.{ .modifier = .always_inline }, tickFn, .{ self, session });
                }

            }).vtable,
        };
    }

    fn tick(self: Callbacks, session: *Self) !void {
        try self.vtable.tick(self.ptr, session);
    }
};

