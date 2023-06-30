const std = @import("std");
const util = @import("util");

const Allocator = std.mem.Allocator;

const time = std.time;
const Timer = time.Timer;
const Session = @This();

const World = @import("World.zig");
const WorldManager = World.Manager;

const Assets = @import("Assets.zig");

const Thread = std.Thread;
const AtomicFlag = util.AtomicFlag;

allocator: Allocator,

world: *World,
world_man: *WorldManager,

// thread: Thread = undefined,
// is_running: AtomicFlag = .{},

timer: Timer = undefined,
tick_count: u64 = 0,
tick_rate: f32 = 60,

pub fn create(allocator: Allocator) !*Session {
    const self = try allocator.create(Session);
    const world = try World.create(allocator);
    const world_man = try WorldManager.create(allocator, world);
    self.* = .{
        .allocator = allocator,
        .world = world,
        .world_man = world_man,
    };
    return self;
}

pub fn destroy(self: *Session) void {
    self.stop();
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.world.destroy();
    self.world_man.destroy();
}

pub fn applyAssets(self: *Session, assets: *const Assets) !void {
    try self.world.leko_data.leko_types.addLekoTypesFromAssetTable(assets.leko_table);
}

pub fn start(self: *Session, ctx: anytype, comptime hooks: Hooks(@TypeOf(ctx))) !void {
    self.timer = try Timer.start();
    if (hooks.on_world_update) |on_world_update| {
        try self.world_man.start(ctx, on_world_update);
    } else {
        try self.world_man.start();
    }
}

pub fn stop(self: *Session) void {
    self.world_man.stop();
}

pub fn Hooks(comptime Ctx: type) type {
    return struct {
        // on_tick: ?HookFunction(Ctx) = null,
        on_world_update: ?WorldManager.OnWorldUpdateFn(Ctx) = null,
    };
}

pub fn HookFunction(comptime Ctx: type) type {
    return fn (Ctx, *Session) anyerror!void;
}

pub fn frameTicks(self: *Session) !u64 {
    const time_ns = self.timer.read();
    const tick_count = @divFloor(time_ns, self.nsPerTick());
    if (tick_count > 0) {
        self.timer.reset();
    }
    for (0..tick_count) |_| {
        try self.tick();
    }
    return tick_count;
}

fn tick(self: *Session) !void {
    try self.world_man.tick();
}

// /// session main loop
// pub fn threadMain(self: *Session, ctx: anytype, comptime hooks: Hooks(@TypeOf(ctx))) !void {
//
//     while (self.isRunning()) : (self.nextTick()) {
//         try self.world_man.tick();
//         if (hooks.on_tick) |on_tick| {
//             try on_tick(ctx, self);
//         }
//     }
//     self.world_man.stop();
// }

// pub fn isRunning(self: Session) bool {
//     return self.is_running.get();
// }

// fn nextTick(self: *Session) void {
//     const elapsed = self.timer.read();
//     const quota = self.nsPerTick();
//     if (elapsed < quota) {
//         time.sleep(quota - elapsed);
//     } else {
//         const extra = elapsed - quota;
//         const elapsed_ms = @divFloor(elapsed, time.ns_per_ms);
//         const extra_ms = @divFloor(extra, time.ns_per_ms);
//         std.log.warn("tick {d} took {d}ms too long ({d}ms total)", .{ self.tick_count, extra_ms, elapsed_ms });
//     }
//     self.tick_count += 1;
//     self.tick_compensation_factor = 1 / self.tickProgressEstimate();
//     if (self.tick_count % 30 == 0) std.log.info("tick_compensation_factor = {d}", .{self.tick_compensation_factor});
//     self.timer.reset();
// }

pub fn nsPerTick(self: Session) u64 {
    return @as(u64, @intFromFloat(std.time.ns_per_s / @as(f64, @floatCast(self.tick_rate))));
}

pub fn tickProgress(self: *Session) f32 {
    return @as(f32, @floatFromInt(self.timer.read() >> 10)) / @as(f32, @floatFromInt(self.nsPerTick() >> 10));
}
