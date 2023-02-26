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

thread: Thread = undefined,
is_running: AtomicFlag = .{},

timer: Timer = undefined,
tick_count: u64 = 0,

tick_rate: f32 = 40,

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
    if (!self.isRunning()) {
        self.is_running.set(true);
        const S = struct {
            fn tMain(s: *Session, c: @TypeOf(ctx)) !void {
                try s.threadMain(c, hooks);
            }
        };
        self.timer = try Timer.start();
        self.tick_count = 0;
        self.thread = try Thread.spawn(.{}, S.tMain, .{self, ctx});
    }
}

pub fn Hooks(comptime Ctx: type) type {
    return struct {
        on_tick: ?HookFunction(Ctx) = null,
        on_world_update: ?WorldManager.OnWorldUpdateFn(Ctx) = null,
    };
}

pub fn HookFunction(comptime Ctx: type) type {
    return fn(Ctx, *Session) anyerror!void;
}


pub fn stop(self: *Session) void {
    if (self.isRunning()) {
        self.is_running.set(false);
        self.thread.join();
    }
}

/// session main loop
pub fn threadMain(
    self: *Session,
    ctx: anytype,
    comptime hooks: Hooks(@TypeOf(ctx))
) !void {
    if (hooks.on_world_update) |on_world_update| {
        try self.world_man.start(ctx, on_world_update);
    }
    else {
        try self.world_man.start();
    }
    while (self.isRunning()) : (self.nextTick()) {
        try self.world_man.tick();
        if (hooks.on_tick) |on_tick| {
            try on_tick(ctx, self);
        }
    }
    self.world_man.stop();
}

pub fn isRunning(self: Session) bool {
    return self.is_running.get();
}

fn nextTick(self: *Session) void {
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

pub fn nsPerTick(self: Session) u64 {
    return @floatToInt(u64, 1_000_000_000 / self.tick_rate);
}

