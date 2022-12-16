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

chunks: Chunks = undefined,
observers: Observers = undefined,
graph: Graph = undefined,

pub const ChunkLoadState = enum {
    deleted,
    loading,
    cancelled,
    active,
    unloading,
};

pub const ChunkStatus = struct {
    load_state: ChunkLoadState = .deleted,
    is_pending: bool = false,
    user_count: Atomic(u32) = .{ .value = 0 },
    mutex: Mutex = .{}
};

pub const ChunkLoadStateEvents = util.Events(union(ChunkLoadState) {
    deleted: Chunk,
    loading: PriorityChunk,
    cancelled: Chunk,
    active: Chunk,
    unloading: Chunk,
});

pub const PriorityChunk = struct {
    chunk: Chunk,
    priority: u32,
};

pub const ChunkStatusStore = util.IjoDataStoreDefaultInit(Chunk, ChunkStatus);

pub fn create(allocator: Allocator) !*World {
    const self = try allocator.create(World);
    self.* = .{
        .allocator = allocator,
    };
    try self.observers.init(allocator);
    try self.chunks.init(allocator);
    try self.graph.init(allocator);
    return self;

}

pub fn destroy(self: *World) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);

    self.chunks.deinit();
    self.observers.deinit();
    self.graph.deinit();

}

pub const Chunks = struct {

    allocator: Allocator,
    pool: ChunkPool,
    statuses: ChunkStatusStore,
    load_state_events: ChunkLoadStateEvents,

    fn init(self: *Chunks, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .pool = ChunkPool.init(allocator),
            .statuses = ChunkStatusStore.init(allocator),
            .load_state_events = ChunkLoadStateEvents.init(allocator),
        };
    }

    fn deinit(self: *Chunks) void {
        self.pool.deinit();
        self.statuses.deinit();
        self.load_state_events.deinit();
    }

    pub fn startUsing(self: *Chunks, chunk: Chunk) void {
        assertOnWorldUpdateThread();
        _ = self.statuses.getPtr(chunk).user_count.fetchAdd(1, .Monotonic);
    }

    pub fn stopUsing(self: *Chunks, chunk: Chunk) void {
        assertOnWorldUpdateThread();
        _ = self.statuses.getPtr(chunk).user_count.fetchSub(1, .Monotonic);
    }

};

pub fn chunkPositionToCenterPosition(chunk_position: Vec3i) Vec3i {
    return chunk_position.mulScalar(chunk_width).addScalar(chunk_width / 2);
}

pub const ChunkPositionStore = util.IjoDataStoreValueInit(Chunk, Vec3i, Vec3i.zero);

pub const Graph = struct {

    allocator: Allocator,
    chunk_positions: ChunkPositionStore,
    position_map: PositionMap(Chunk) = .{},

    position_map_mutex: Mutex = .{},

    fn init(self: *Graph, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .chunk_positions = ChunkPositionStore.init(allocator),
        };
    }

    fn deinit(self: *Graph) void {
        const allocator = self.allocator;
        self.chunk_positions.deinit();
        self.position_map.deinit(allocator);
    }
};

pub fn PositionMap(comptime V: type) type {
    return std.HashMapUnmanaged(Vec3i, V, struct {
        pub fn hash(_: @This(), v: Vec3i) u64 {
            var h: u64 = @bitCast(u32, v.v[0]);
            h = (h << 20) ^ @bitCast(u32, v.v[1]);
            h = (h << 20) ^ @bitCast(u32, v.v[2]);
            return h;
        }
        pub fn eql(_: @This(), a: Vec3i, b: Vec3i) bool {
            return a.eql(b);
        }
    }, std.hash_map.default_max_load_percentage);
}

pub const Observer = util.Ijo("world observer");
pub const ObserverPool = util.IjoPool(Observer);

const ObserverZone = struct {
    mutex: Mutex = .{},
    position: Vec3i = Vec3i.zero,
    center_chunk_position: Vec3i = Vec3i.zero,

    fn setPosition(self: *ObserverZone, position: Vec3i) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.position = position;
    }

    pub fn getPosition(self: *ObserverZone) Vec3i {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.position;
    }

    fn updateCenterChunkPosition(self: *ObserverZone) struct { old: Vec3i, new: Vec3i } {
        self.mutex.lock();
        defer self.mutex.unlock();
        const old_center_position = self.center_chunk_position;
        self.center_chunk_position = self.position.divFloorScalar(chunk_width);
        return .{
            .old = old_center_position,
            .new = self.center_chunk_position,
        };
    }
};

pub const ObserverState = enum(u8) {
    deleted,
    creating,
    active,
    deleting,
};

const ObserverStatus = struct {
    state: Atomic(ObserverState) = .{ .value = .deleted },
    is_dirty: Atomic(bool) = .{ .value = false },
    index: Atomic(usize) = .{ .value = 0 },
};


const ObserverZoneStore = util.IjoDataStoreDefaultInit(Observer, ObserverZone);
const ObserverStatusStore = util.IjoDataStoreDefaultInit(Observer, ObserverStatus);

pub const Observers = struct {

    allocator: Allocator,
    pool: ObserverPool,
    mutex: Mutex = .{},

    observer_list: List(Observer) = .{},

    zones: ObserverZoneStore,
    statuses: ObserverStatusStore,


    fn init(self: *Observers, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .pool = ObserverPool.init(allocator),
            .zones = ObserverZoneStore.init(allocator),
            .statuses = ObserverStatusStore.init(allocator),
        };
    }

    fn deinit(self: *Observers) void {
        const allocator = self.allocator;
        self.pool.deinit();
        self.zones.deinit();
        self.statuses.deinit();
        self.observer_list.deinit(allocator);
    }

    fn matchDataCapacity(self: *Observers) !void {
        try self.zones.matchCapacity(self.pool);
        try self.statuses.matchCapacity(self.pool);
    }

    pub fn create(self: *Observers, initial_position: Vec3i) !Observer {
        self.mutex.lock();
        defer self.mutex.unlock();

        const observer = try self.pool.create();
        try self.matchDataCapacity();

        const status = self.statuses.getPtr(observer);
        status.state.store(.creating, .Monotonic);
        status.index.store(self.observer_list.items.len, .Monotonic);
        status.is_dirty.store(true, .Monotonic);

        const zone = self.zones.getPtr(observer);
        zone.setPosition(initial_position);

        try self.observer_list.append(self.allocator, observer);
        return observer;
    }

    pub fn delete(self: *Observers, observer: Observer) !void {
        const status = self.statuses.getPtr(observer);
        status.state.store(.deleting, .Monotonic);
        status.is_dirty.store(true, .Monotonic);
    }

    pub fn setPosition(self: *Observers, observer: Observer, position: Vec3i) void {
        const zone = self.zones.getPtr(observer);
        zone.mutex.lock();
        defer zone.mutex.unlock();
        zone.position = position;
        const load_center_position = chunkPositionToCenterPosition(zone.center_chunk_position);
        if (position.sub(load_center_position).mag2() > chunk_width * chunk_width) {
            self.statuses.getPtr(observer).is_dirty.store(true, .Monotonic);
        }
    }

    pub fn getPosition(self: *Observers, observer: Observer) Vec3i {
        return self.zones.getPtr(observer).getPosition();
    }

    fn count(self: *Observers) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.observer_list.items.len;
    }

    fn get(self: *Observers, i: usize) Observer {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.observer_list.items[i];
    }

    fn swapRemoveAndDelete(self: *Observers, i: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const observer = self.observer_list.swapRemove(i);
        self.pool.delete(observer);
    }



};

threadlocal var on_world_update_thread: bool = false;

pub fn assertOnWorldUpdateThread() callconv(.Inline) void {
    std.debug.assert(on_world_update_thread);
}

pub const Manager = struct {

    allocator: Allocator,
    world: *World,

    update_thread: Thread = undefined,
    thread_is_running: Atomic(bool) = Atomic(bool).init(false),


    pending_chunks: List(Chunk) = .{},

    pub fn OnWorldUpdateFn(comptime Context: type) type {
        return fn(Context, *World) anyerror!void;
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
        self.pending_chunks.deinit(allocator);
    }

    pub fn start(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        if (self.thread_is_running.load(.Monotonic)) {
            @panic("world manager update thread already running");
        }
        self.thread_is_running.store(true, .Monotonic);
        self.update_thread = try Thread.spawn(.{}, (struct {
            fn f(s: *Manager, c: @TypeOf(context)) !void {
                try s.threadMain(c, on_update_fn);
            }
        }).f, .{self, context});
    }

    pub fn stop(self: *Manager) void {
        if (self.thread_is_running.load(.Monotonic)) {
            self.thread_is_running.store(false, .Monotonic);
            self.update_thread.join();
        }
    }

    fn threadMain(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        on_world_update_thread = true;
        while (self.thread_is_running.load(.Monotonic)) {

            try self.processPendingChunks();
            try self.processDirtyObservers();

            try on_update_fn(context, self.world);
        }
    }

    fn processPendingChunks(self: *Manager) !void {
        const world = self.world;
        const chunks = &world.chunks;
        const pending_chunks = &self.pending_chunks.items;
            var i: usize = 0;
            while (i < pending_chunks.len) {
                const chunk = pending_chunks.*[i];
                const status = chunks.statuses.getPtr(chunk);
                // status.mutex.lock();
                // defer status.mutex.unlock();
                if (status.user_count.load(.Monotonic) != 0) {
                    i += 1;
                    continue;
                }
                switch (status.load_state) {
                    .deleted => {
                        @panic("deleted chunk marked as pending");
                    },
                    .loading => {
                        status.load_state = .active;
                        status.is_pending = false;
                        try chunks.load_state_events.post(.active, chunk);
                    },
                    .cancelled => {
                        status.load_state = .unloading;
                        try chunks.load_state_events.post(.unloading, chunk);
                    },
                    .active => {
                        status.load_state = .unloading;
                        try chunks.load_state_events.post(.unloading, chunk);
                    },
                    .unloading => {
                        status.load_state = .deleted;
                        status.is_pending = false;
                        try chunks.load_state_events.post(.deleted, chunk);
                    },
                }
                if (status.is_pending) {
                    i += 1;
                }
                else {
                    _ = self.pending_chunks.swapRemove(i);
                }
            }

    }

    fn processDirtyObservers(self: *Manager) !void {
        const world = self.world;
        const observers = &world.observers;
        var i: usize = 0;
        while (i < observers.count()) {
            const observer = observers.get(i);
            const status = observers.statuses.getPtr(observer);

            if (!status.is_dirty.load(.Monotonic)) {
                i += 1;
                continue;
            }

            status.is_dirty.store(false, .Monotonic);

            const state = status.state.load(.Monotonic);
            const zone = observers.zones.getPtr(observer);

            if (state != .deleting) {
                i += 1;
            }
            switch (state) {
                .deleted => @panic("deleted observer marked as dirty"),
                .creating => {
                    status.state.store(.active, .Monotonic);
                    const center_position = zone.updateCenterChunkPosition().new;
                    std.log.info("{} created at {d}", .{observer, center_position});
                },
                .active => {
                    const center_position = zone.updateCenterChunkPosition();
                    std.log.info("{} moved from {d} to {d}", .{observer, center_position.new, center_position.old });
                },
                .deleting => {
                    status.state.store(.deleted, .Monotonic);
                    observers.swapRemoveAndDelete(i);
                },
            }
        }
    }

    pub fn tick(self: *Manager) !void {
        _ = self;
    }
};