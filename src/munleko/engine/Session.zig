const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;

const Allocator = std.mem.Allocator;

const Timer = std.time.Timer;
const Session = @This();

const World = @import("World.zig");
const WorldManager = World.Manager;

const Assets = @import("Assets.zig");
const Player = @import("Player.zig");

const Thread = std.Thread;
const AtomicFlag = util.AtomicFlag;

allocator: Allocator,

world: *World,
world_man: *WorldManager,
player: Player,
// thread: Thread = undefined,
// is_running: AtomicFlag = .{},

tick_timer: TickTimer = .{ .rate = 40 },
tick_count: u64 = 0,

pub fn create(allocator: Allocator) !*Session {
    const self = try allocator.create(Session);
    const world = try World.create(allocator);
    errdefer world.destroy();
    const world_man = try WorldManager.create(allocator, world);
    errdefer world_man.destroy();
    const player = try Player.init(world, Vec3.zero);
    errdefer player.deinit();
    self.* = .{
        .allocator = allocator,
        .world = world,
        .world_man = world_man,
        .player = player,
    };
    return self;
}

pub fn destroy(self: *Session) void {
    self.stop();
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.player.deinit();
    self.world.destroy();
    self.world_man.destroy();
}

pub fn applyAssets(self: *Session, assets: *Assets) !void {
    const world_leko_types = &self.world.leko_data.leko_types;
    world_leko_types.deinit();
    try world_leko_types.dupe(self.allocator, &assets.leko_type_table);
}

pub fn start(self: *Session, ctx: anytype, comptime hooks: Hooks(@TypeOf(ctx))) !void {
    self.tick_timer.reset();
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

pub fn tick(self: *Session) !void {
    try self.player.tick(self);
    try self.world_man.tick();
}

pub fn tickProgress(self: *Session) f32 {
    const time = self.tick_timer.read();
    const tick_rate_f64: f64 = @floatCast(self.tick_rate);
    return @floatCast(time * tick_rate_f64);
}

const TickTimer = struct {
    last_time: i64 = 0,
    rate: f32,

    fn reset(self: *TickTimer) void {
        self.last_time = std.time.microTimestamp();
    }

    fn read(self: TickTimer) f32 {
        const last_time: f64 = @floatFromInt(self.last_time);
        const time: f64 = @floatFromInt(std.time.microTimestamp());
        return @floatCast((time - last_time) / std.time.us_per_s);
    }

    pub fn progress(self: TickTimer) f32 {
        const time = self.read();
        return time * self.rate;
    }

    fn countTicks(self: TickTimer) u32 {
        const prog = self.progress();
        const count: u32 = @intFromFloat(@floor(prog));
        return count;
    }

    pub fn countTicksAndReset(self: *TickTimer) u32 {
        const ticks = self.countTicks();
        self.last_time += @as(i64, ticks) * self.usPerTick();
        return ticks;
    }

    fn usPerTick(self: TickTimer) i64 {
        const us = std.time.us_per_s / self.rate;
        return @intFromFloat(us);
    }
};
