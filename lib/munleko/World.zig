const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Engine = @import("Engine.zig");
const Session = @import("Session.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const List = std.ArrayListUnmanaged;

const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Atomic = std.atomic.Atomic;

const World = @This();

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

pub const Chunk = util.Ijo("world chunk");
pub const ChunkPool = util.IjoPool(Chunk);

pub const chunk_width_bits = 5;
pub const chunk_width = 1 << chunk_width_bits;

allocator: Allocator,
chunk_pool: ChunkPool,

observers: Observers = undefined,


pub fn create(allocator: Allocator) !*World {
    const self = try allocator.create(World);
    self.* = .{
        .allocator = allocator,
        .chunk_pool = ChunkPool.init(allocator),
    };
    try self.observers.init(allocator);
    return self;

}

pub fn destroy(self: *World) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);

    self.chunk_pool.deinit();
    self.observers.deinit();

}


pub const Observer = util.Ijo("world observer");
pub const ObserverPool = util.IjoPool(Observer);

const ObserverZone = struct {
    center_chunk_pos: Vec3i = Vec3i.zero,
};

fn IjoIndicesStore(comptime I: type) type {
    return util.IjoDataStoreValueInit(I, usize, 0);
}

const ObserverZoneDataStore = util.IjoDataStoreDefaultInit(Observer, ObserverZone);
const ObserverPositionDataStore = util.IjoDataStoreValueInit(Observer, Vec3, Vec3.zero);

const ObserverEvents = util.EventsUnmanaged(union(enum) {
    add: struct { observer: Observer, position: Vec3 },
    remove: Observer,
});

pub const Observers = struct {

    allocator: Allocator,
    pool: ObserverPool,

    active_list: List(Observer) = .{},

    zones: ObserverZoneDataStore,
    positions: ObserverPositionDataStore,
    indices: IjoIndicesStore(Observer),


    fn init(self: *Observers, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .pool = ObserverPool.init(allocator),
            .zones = ObserverZoneDataStore.init(allocator),
            .positions = ObserverPositionDataStore.init(allocator),
            .indices = IjoIndicesStore(Observer).init(allocator),
        };
    }

    fn deinit(self: *Observers) void {
        const allocator = self.allocator;
        self.pool.deinit();
        self.zones.deinit();
        self.positions.deinit();
        self.indices.deinit();
        self.active_list.deinit(allocator);
    }

    fn matchDataCapacity(self: *Observers) !void {
        try self.zones.matchCapacity(self.pool);
        try self.indices.matchCapacity(self.pool);
        try self.positions.matchCapacity(self.pool);
    }

    
};

pub const Manager = struct {
    
    allocator: Allocator,
    world: *World,

    update_thread: Thread = undefined,
    thread_is_running: Atomic(bool) = Atomic(bool).init(false),

    observer_events: ObserverEvents = .{},
    /// locked when processing observer add/remove events
    observer_mutex: Mutex = .{},

    pub fn OnWorldUpdateFn(comptime Context: type) type {
        return fn(Context, *Manager) anyerror!void;
    }

    pub fn create(allocator: Allocator, world: *World) !*Manager {
        const self = try allocator.create(Manager);
        self.* = .{
            .allocator = allocator,
            .world = world,
        };
        return self;
    }

    pub fn destroy(self: *Manager) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.stop();
        self.observer_events.deinit(allocator);
    }

    pub fn start(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        if (!self.thread_is_running.load(.Monotonic)) {
            self.thread_is_running.store(true, .Monotonic);
            self.update_thread = try Thread.spawn(.{}, (struct {
                fn f(s: *Manager, c: @TypeOf(context)) !void {
                    try s.threadMain(c, on_update_fn);
                }
            }).f, .{self, context});
        }
        else {
            @panic("world manager update thread already running");
        }
    }

    pub fn stop(self: *Manager) void {
        if (self.thread_is_running.load(.Monotonic)) {
            self.thread_is_running.store(false, .Monotonic);
            self.update_thread.join();
        }
    }

    pub fn addObserver(self: *Manager, position: Vec3) !Observer {
        const world = self.world;
        self.observer_mutex.lock();
        defer self.observer_mutex.unlock();
        const observer = try world.observers.pool.create();
        try self.observer_events.post(self.allocator, .add, .{
            .observer = observer,
            .position = position,
        });
        return observer;
    }

    pub fn removeObserver(self: *Manager, observer: Observer) !void {
        self.observer_mutex.lock();
        defer self.observer_mutex.unlock();
        try self.observer_events.post(self.allocator, .remove, observer);
    }

    /// must be called from world update thread
    pub fn setObserverPosition(self: *Manager, observer: Observer, position: Vec3) void {
        const observers = &self.world.observers;
        observers.positions.getPtr(observer).* = position;
    }

    fn threadMain(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        const world = self.world;
        while (self.thread_is_running.load(.Monotonic)) {
            {
                self.observer_mutex.lock();
                defer self.observer_mutex.unlock();
                try world.observers.matchDataCapacity();
                const allocator = world.observers.allocator;
                const active_list = &world.observers.active_list;
                for (self.observer_events.get(.add)) |add_event| {
                    const observer = add_event.observer;
                    const position = add_event.position;
                    const i = active_list.items.len;
                    try active_list.append(allocator, add_event.observer);
                    world.observers.indices.getPtr(observer).* = i;
                    const zone = world.observers.zones.getPtr(observer);
                    zone.center_chunk_pos = position.divScalar(chunk_width).round().cast(i32);
                    std.log.info("observer added at {d}", .{zone.center_chunk_pos});
                }
                for (self.observer_events.get(.remove)) |observer| {
                    const index = world.observers.indices.get(observer);
                    const last_observer = active_list.items[active_list.items.len - 1];
                    active_list.items[index] = last_observer;
                    world.observers.indices.getPtr(last_observer).* = index;
                    active_list.items.len -= 1;
                    world.observers.pool.destroy(observer);
                }
                self.observer_events.clearAll();
            }
            for (world.observers.active_list.items) |observer| {
                const zone = world.observers.zones.getPtr(observer);
                const position = world.observers.positions.get(observer);
                const load_center_position = zone.center_chunk_pos.mulScalar(chunk_width).cast(f32);
                if (position.sub(load_center_position).mag2() > chunk_width * chunk_width) {
                    const prev_center_chunk_pos = zone.center_chunk_pos;
                    zone.center_chunk_pos = position.divScalar(chunk_width).round().cast(i32);
                    std.log.info("observer moved from {d} to {d}", .{prev_center_chunk_pos, zone.center_chunk_pos});
                }
            }
            try on_update_fn(context, self);
        }
    }

    pub fn tick(self: *Manager) !void {
        _ = self;
    }
};