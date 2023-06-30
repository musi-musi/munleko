const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Engine = @import("../Engine.zig");
const Session = @import("Session.zig");
const leko = @import("leko.zig");
const Physics = @import("Physics.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const List = std.ArrayListUnmanaged;

const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Atomic = std.atomic.Atomic;
const AtomicFlag = util.AtomicFlag;
const ResetEvent = Thread.ResetEvent;

const ThreadGroup = util.ThreadGroup;

const World = @This();

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const LekoData = leko.LekoData;

const Range3i = nm.Range3i;

pub const Chunk = util.Ijo("world chunk");
const ChunkPool = util.IjoPool(Chunk);

pub const chunk_width_bits = 5;
pub const chunk_width = 1 << chunk_width_bits;

const assert = std.debug.assert;

allocator: Allocator,
dirty_event: ResetEvent = .{},

chunks: Chunks = undefined,
graph: Graph = undefined,
leko_data: LekoData = undefined,
observers: Observers = undefined,
physics: Physics = undefined,

pub fn create(allocator: Allocator) !*World {
    const self = try allocator.create(World);
    self.* = .{
        .allocator = allocator,
    };
    try self.chunks.init(self);
    try self.graph.init(self);
    try self.observers.init(self);
    try self.leko_data.init(self);
    self.physics.init(self);
    return self;
}

pub fn destroy(self: *World) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.chunks.deinit();
    self.graph.deinit();
    self.observers.deinit();
    self.leko_data.deinit();
    self.physics.deinit();
}

fn createChunk(self: *World) !Chunk {
    const chunk = try self.chunks.pool.create();
    errdefer self.chunks.pool.delete(chunk);
    try self.chunks.matchDataCapacity();
    try self.graph.matchDataCapacity();
    try self.leko_data.matchDataCapacity();
    return chunk;
}

fn poolDeleteChunk(self: *World, chunk: Chunk) void {
    self.chunks.pool.delete(chunk);
}

pub const ChunkLoadState = enum {
    deleted,
    loading,
    active,
    unloading,
};

pub const ChunkStatus = struct {
    mutex: Mutex = .{},
    generation: u32 = 0,
    load_state: ChunkLoadState = .deleted,
    user_count: u32 = 0,
    observer_count: u32 = 0,
};

pub const ChunkLoadStateEvents = util.Events(union(enum) {
    loading: PriorityChunk,
    active: Chunk,
    unloading: Chunk,
});

pub const PriorityChunk = struct {
    chunk: Chunk,
    priority: i32,
};

const ChunkStatusStore = util.IjoDataStoreDefaultInit(Chunk, ChunkStatus);

pub const Chunks = struct {
    world: *World,
    pool: ChunkPool,
    statuses: ChunkStatusStore,

    load_state_events: ChunkLoadStateEvents,

    fn init(self: *Chunks, world: *World) !void {
        self.* = .{
            .world = world,
            .pool = ChunkPool.init(world.allocator),
            .statuses = ChunkStatusStore.init(world.allocator),
            .load_state_events = ChunkLoadStateEvents.init(world.allocator),
        };
    }

    fn deinit(self: *Chunks) void {
        self.pool.deinit();
        self.statuses.deinit();
        self.load_state_events.deinit();
    }

    fn matchDataCapacity(self: *Chunks) !void {
        try self.statuses.matchCapacity(self.pool);
    }

    pub fn startUsingChunk(self: *Chunks, chunk: Chunk) void {
        const status = self.statuses.getPtr(chunk);
        status.mutex.lock();
        defer status.mutex.unlock();
        status.user_count += 1;
    }

    pub fn tryStartUsingChunk(self: *Chunks, chunk: Chunk, generation: u32) bool {
        const status = self.statuses.getPtr(chunk);
        status.mutex.lock();
        defer status.mutex.unlock();
        if (status.generation != generation) {
            return false;
        }
        status.user_count += 1;
        return true;
    }

    pub fn stopUsingChunk(self: *Chunks, chunk: Chunk) void {
        const status = self.statuses.getPtr(chunk);
        status.mutex.lock();
        defer status.mutex.unlock();
        status.user_count -= 1;
        if (status.user_count == 0) {
            self.world.dirty_event.set();
        }
    }
};

pub const ChunkPositionStore = util.IjoDataStoreValueInit(Chunk, Vec3i, Vec3i.zero);
pub const ChunkPositionMap = std.AutoHashMapUnmanaged(Vec3i, Chunk);

pub const ChunkNeighbors = [6]?Chunk;

pub const ChunkNeighborsStore = util.IjoDataStoreValueInit(Chunk, ChunkNeighbors, std.mem.zeroes(ChunkNeighbors));

pub const Graph = struct {
    world: *World,

    positions: ChunkPositionStore,
    neighbors: ChunkNeighborsStore,

    position_map: ChunkPositionMap = .{},
    position_map_mutex: Mutex = .{},

    fn init(self: *Graph, world: *World) !void {
        self.* = .{
            .world = world,
            .positions = ChunkPositionStore.init(world.allocator),
            .neighbors = ChunkNeighborsStore.init(world.allocator),
        };
    }

    fn deinit(self: *Graph) void {
        const allocator = self.world.allocator;
        self.positions.deinit();
        self.neighbors.deinit();
        self.position_map.deinit(allocator);
    }

    pub fn chunkAt(self: *Graph, position: Vec3i) ?Chunk {
        self.position_map_mutex.lock();
        defer self.position_map_mutex.unlock();
        return self.position_map.get(position);
    }

    pub fn neighborChunk(self: *Graph, chunk: Chunk, direction: nm.Cardinal3) ?Chunk {
        return self.neighbors.get(chunk)[@intFromEnum(direction)];
    }

    fn matchDataCapacity(self: *Graph) !void {
        const pool = self.world.chunks.pool;
        try self.positions.matchCapacity(pool);
        try self.neighbors.matchCapacity(pool);
    }

    fn addChunk(self: *Graph, chunk: Chunk, position: Vec3i) !void {
        self.positions.getPtr(chunk).* = position;
        self.position_map_mutex.lock();
        defer self.position_map_mutex.unlock();
        try self.position_map.put(self.world.allocator, position, chunk);
        const neighbors = self.neighbors.getPtr(chunk);
        inline for (comptime std.enums.values(nm.Cardinal3)) |direction| {
            const neighbor_position = position.add(Vec3i.unitSigned(direction));
            const neighbor_opt = self.position_map.get(neighbor_position);
            neighbors.*[@intFromEnum(direction)] = neighbor_opt;
            if (neighbor_opt) |neighbor| {
                self.neighbors.getPtr(neighbor).*[@intFromEnum(direction.negate())] = chunk;
            }
        }
    }

    fn removeChunk(self: *Graph, position: Vec3i) void {
        self.position_map_mutex.lock();
        defer self.position_map_mutex.unlock();
        _ = self.position_map.remove(position);
        inline for (comptime std.enums.values(nm.Cardinal3)) |direction| {
            const neighbor_position = position.add(Vec3i.unitSigned(direction));
            if (self.position_map.get(neighbor_position)) |neighbor| {
                self.neighbors.getPtr(neighbor).*[@intFromEnum(direction.negate())] = null;
            }
        }
    }
};

pub const Observer = util.Ijo("world observer");
const ObserverPool = util.IjoPool(Observer);

pub const ObserverState = enum(u8) {
    deleted,
    creating,
    active,
    deleting,
};

const ObserverStatus = struct {
    state: Atomic(ObserverState) = .{ .value = .deleted },
    is_dirty: AtomicFlag = .{},
};

pub const ObserverStatusStore = util.IjoDataStoreDefaultInit(Observer, ObserverStatus);

const ObserverZone = struct {
    mutex: Mutex = .{},
    position: Vec3i = Vec3i.zero,
    center_chunk_position: Vec3i = Vec3i.zero,
    load_radius: u32 = 6,

    fn getPosition(self: *ObserverZone) Vec3i {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.position;
    }

    fn setPosition(self: *ObserverZone, position: Vec3i) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.position = position;
    }
};

fn observerZoneRange(center: Vec3i, radius: u32) Range3i {
    return Range3i.init(
        center.subScalar(@as(i32, @intCast(radius))).v,
        center.addScalar(@as(i32, @intCast(radius))).v,
    );
}

fn positionToChunkCenterPosition(position: Vec3i) Vec3i {
    return position
        .cast(f32)
        .divScalar(chunk_width)
        .round()
        .cast(i32);
}

const ObserverZoneStore = util.IjoDataStoreDefaultInit(Observer, ObserverZone);

const ObserverChunkMap = std.HashMap(Chunk, void, Chunk.HashContext, std.hash_map.default_max_load_percentage);

const ObserverChunkMaps = struct {
    loading: ObserverChunkMap,
    active: ObserverChunkMap,
};

const ObserverChunkMapStore = util.IjoDataStore(Observer, *ObserverChunkMaps, struct {
    pub fn initData(_: @This(), arena: *std.heap.ArenaAllocator) !*ObserverChunkMaps {
        const maps = try arena.allocator().create(ObserverChunkMaps);
        maps.* = ObserverChunkMaps{
            .loading = ObserverChunkMap.init(arena.child_allocator),
            .active = ObserverChunkMap.init(arena.child_allocator),
        };
        return maps;
    }

    pub fn deinitData(_: @This(), maps: **ObserverChunkMaps) void {
        maps.*.loading.deinit();
        maps.*.active.deinit();
    }
});

const ObserverChunkEventsStore = util.IjoEventsStore(Observer, union(enum) {
    enter: Chunk,
    exit: Chunk,
});

pub const Observers = struct {
    world: *World,
    pool: ObserverPool,

    statuses: ObserverStatusStore,
    zones: ObserverZoneStore,
    chunk_maps: ObserverChunkMapStore,
    chunk_events: ObserverChunkEventsStore,

    list: List(Observer) = .{},
    mutex: Mutex = .{},

    fn init(self: *Observers, world: *World) !void {
        self.* = .{
            .world = world,
            .pool = ObserverPool.init(world.allocator),
            .statuses = ObserverStatusStore.init(world.allocator),
            .zones = ObserverZoneStore.init(world.allocator),
            .chunk_maps = ObserverChunkMapStore.init(world.allocator),
            .chunk_events = ObserverChunkEventsStore.init(world.allocator),
        };
    }

    fn deinit(self: *Observers) void {
        self.pool.deinit();

        self.statuses.deinit();
        self.zones.deinit();
        self.chunk_maps.deinit();
        self.chunk_events.deinit();

        self.list.deinit(self.world.allocator);
    }

    fn count(self: *Observers) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.list.items.len;
    }

    fn atIndex(self: *Observers, i: usize) Observer {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.list.items[i];
    }

    fn swapRemove(self: *Observers, i: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.list.swapRemove(i);
    }

    pub fn setPosition(self: *Observers, observer: Observer, position: Vec3i) void {
        const status = self.statuses.getPtr(observer);
        const zone = self.zones.getPtr(observer);
        zone.setPosition(position);
        status.is_dirty.set(true);
        self.world.dirty_event.set();
    }

    pub fn create(self: *Observers, position: Vec3i) !Observer {
        self.mutex.lock();
        defer self.mutex.unlock();
        const observer = try self.pool.create();

        try self.statuses.matchCapacity(self.pool);
        try self.zones.matchCapacity(self.pool);
        try self.chunk_maps.matchCapacity(self.pool);
        try self.chunk_events.matchCapacity(self.pool);

        const status = self.statuses.getPtr(observer);
        status.state.store(.creating, .Monotonic);
        status.is_dirty.set(true);
        const chunk_maps = self.chunk_maps.get(observer);
        chunk_maps.*.loading.clearRetainingCapacity();
        chunk_maps.*.active.clearRetainingCapacity();
        const zone = self.zones.getPtr(observer);
        zone.position = position;
        try self.list.append(self.world.allocator, observer);
        self.world.dirty_event.set();
        return observer;
    }

    pub fn delete(self: *Observers, observer: Observer) void {
        const status = self.statuses.getPtr(observer);
        status.state.store(.deleting, .Monotonic);
        status.is_dirty.set(true);
        self.world.dirty_event.set();
    }

    fn poolDelete(self: *Observers, observer: Observer) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.pool.delete(observer);
    }
};

pub const Manager = struct {
    allocator: Allocator,
    world: *World,

    thread: Thread = undefined,
    is_running: AtomicFlag = .{},

    unloading_chunks: List(Chunk) = .{},

    loader: *Loader,

    const LoadRange = struct {
        observer: Observer,
        range: Range3i,
    };

    const LoadRangeEvents = util.Events(union(enum) {
        load: LoadRange,
        unload: LoadRange,
    });

    pub fn create(allocator: Allocator, world: *World) !*Manager {
        const self = try allocator.create(Manager);
        self.* = .{
            .allocator = allocator,
            .world = world,
            .loader = try Loader.create(allocator, world),
        };
        return self;
    }

    pub fn destroy(self: *Manager) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.unloading_chunks.deinit(allocator);
        self.loader.destroy();
    }

    pub fn OnWorldUpdateFn(comptime Context: type) type {
        return fn (Context, *World) anyerror!void;
    }

    pub fn start(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        const Context = @TypeOf(context);
        const thread_main = (struct {
            fn f(s: *Manager, c: Context) !void {
                try s.threadMain(c, on_update_fn);
            }
        }).f;

        if (self.is_running.get()) {
            @panic("world manager is already running");
        }
        self.is_running.set(true);
        self.thread = try Thread.spawn(.{}, thread_main, .{ self, context });
        try self.loader.start();
    }

    pub fn stop(self: *Manager) void {
        if (!self.is_running.get()) {
            return;
        }
        self.is_running.set(false);
        self.world.dirty_event.set();
        self.thread.join();
        self.loader.stop();
    }

    fn threadMain(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        var load_range_events = LoadRangeEvents.init(self.allocator);
        defer load_range_events.deinit();

        var loading_chunks = List(Chunk){};
        defer loading_chunks.deinit(self.allocator);

        while (self.is_running.get()) {
            self.world.dirty_event.wait();
            self.world.dirty_event.reset();
            try self.processUnloadingChunks();
            try self.processLoadingChunks();
            self.world.chunks.load_state_events.clearAll();
            try self.processObservers(&load_range_events);
            try self.processLoadRangeEvents(&load_range_events);
            try on_update_fn(context, self.world);
            self.world.leko_data.clearEvents();
        }
    }

    fn processUnloadingChunks(self: *Manager) !void {
        var i: usize = 0;
        while (i < self.unloading_chunks.items.len) {
            const chunk = self.unloading_chunks.items[i];
            i += 1;
            const status = self.world.chunks.statuses.getPtr(chunk);
            if (!status.mutex.tryLock()) {
                // skip chunk if its currently being used somewhere
                continue;
            }
            defer status.mutex.unlock();
            if (status.user_count > 0) {
                // skip chunk if its currently being used somewhere
                continue;
            }
            self.world.poolDeleteChunk(chunk);
            i -= 1;
            _ = self.unloading_chunks.swapRemove(i);
        }
    }

    fn processLoadingChunks(self: *Manager) !void {
        const load_state_events = &self.world.chunks.load_state_events;
        load_state_events.clear(.active);
        var finished_chunks = std.ArrayList(Chunk).init(self.allocator);
        defer finished_chunks.deinit();
        try self.loader.processChunkLoadStateEvents(&finished_chunks);
        defer finished_chunks.clearRetainingCapacity();
        for (finished_chunks.items) |chunk| {
            const status = self.world.chunks.statuses.getPtr(chunk);
            if (status.load_state != .loading) {
                continue;
            }
            status.mutex.lock();
            defer status.mutex.unlock();
            status.load_state = .active;
            try load_state_events.post(.active, chunk);
        }
    }

    fn processObservers(self: *Manager, load_range_events: *LoadRangeEvents) !void {
        const world = self.world;
        const observers = &world.observers;
        var i: usize = 0;
        while (i < observers.count()) {
            const observer = observers.atIndex(i);
            i += 1;
            const status = observers.statuses.getPtr(observer);
            const state = status.state.load(.Monotonic);
            const zone = observers.zones.getPtr(observer);
            if (state == .active) {
                const events = observers.chunk_events.get(observer);
                events.clearAll();
                try self.processActiveObserverMaps(observer);
            }
            if (!status.is_dirty.get()) {
                continue;
            }
            status.is_dirty.set(false);
            switch (state) {
                .creating => {
                    const position = zone.getPosition();
                    const center_position = positionToChunkCenterPosition(position);
                    zone.center_chunk_position = center_position;
                    try load_range_events.post(.load, .{
                        .observer = observer,
                        .range = observerZoneRange(center_position, zone.load_radius),
                    });
                    status.state.store(.active, .Monotonic);
                },
                .active => {
                    const position = zone.getPosition();

                    const old_center_position = zone.center_chunk_position;

                    const distance = position.sub(old_center_position.mulScalar(chunk_width)).cast(f32).mag();
                    if (distance < chunk_width) {
                        continue;
                    }
                    const new_center_position = positionToChunkCenterPosition(position);

                    zone.center_chunk_position = new_center_position;
                    try load_range_events.post(.load, .{
                        .observer = observer,
                        .range = observerZoneRange(new_center_position, zone.load_radius),
                    });
                    try load_range_events.post(.unload, .{
                        .observer = observer,
                        .range = observerZoneRange(old_center_position, zone.load_radius),
                    });
                },
                .deleting => {
                    try load_range_events.post(.unload, .{
                        .observer = observer,
                        .range = observerZoneRange(zone.center_chunk_position, zone.load_radius),
                    });
                    status.state.store(.deleted, .Monotonic);
                },
                .deleted => {
                    observers.pool.delete(observer);
                    i -= 1;
                    observers.swapRemove(i);
                },
            }
        }
    }

    fn processActiveObserverMaps(self: *Manager, observer: Observer) !void {
        const world = self.world;
        const observers = &world.observers;
        const chunks = &world.chunks;
        const maps = observers.chunk_maps.get(observer);
        const chunk_events = observers.chunk_events.get(observer);
        var loading_iter = maps.loading.keyIterator();
        while (loading_iter.next()) |chunk| {
            const status = chunks.statuses.getPtr(chunk.*);
            switch (status.load_state) {
                .loading => {},
                .active => {
                    try maps.active.put(chunk.*, {});
                    try chunk_events.post(.enter, chunk.*);
                },
                .unloading => {},
                .deleted => unreachable,
            }
        }
        var active_iter = maps.active.keyIterator();
        while (active_iter.next()) |chunk| {
            _ = maps.loading.remove(chunk.*);
        }
    }

    fn processLoadRangeEvents(self: *Manager, events: *LoadRangeEvents) !void {
        const load_state_events = &self.world.chunks.load_state_events;
        defer events.clearAll();
        load_state_events.clear(.loading);
        for (events.get(.load)) |event| {
            var iter = event.range.iterate();
            while (iter.next()) |position| {
                try self.processObserverChunkLoad(event.observer, position);
            }
        }
        load_state_events.clear(.unloading);
        for (events.get(.unload)) |event| {
            var iter = event.range.iterate();
            while (iter.next()) |position| {
                try self.processObserverChunkUnload(event.observer, position);
            }
        }
    }

    fn processObserverChunkLoad(self: *Manager, observer: Observer, chunk_position: Vec3i) !void {
        const world = self.world;
        const chunks = &world.chunks;
        const graph = &world.graph;
        const observers = &world.observers;
        const maps = observers.chunk_maps.get(observer);
        const events = observers.chunk_events.get(observer);
        if (graph.position_map.get(chunk_position)) |chunk| {
            // if the chunk is already mapped in this observer, we dont need to do anything
            if (maps.loading.contains(chunk) or maps.active.contains(chunk)) {
                return;
            }
            const chunk_status = chunks.statuses.getPtr(chunk);
            chunk_status.mutex.lock();
            defer chunk_status.mutex.unlock();
            chunk_status.observer_count += 1;
            switch (chunk_status.load_state) {
                .loading => {
                    try maps.loading.put(chunk, {});
                },
                .active => {
                    try maps.active.put(chunk, {});
                    try events.post(.enter, chunk);
                },
                else => unreachable,
            }
        } else {
            const chunk = try world.createChunk();
            const chunk_status = chunks.statuses.getPtr(chunk);
            chunk_status.load_state = .loading;
            chunk_status.observer_count = 1;
            chunk_status.user_count = 0;
            try maps.loading.put(chunk, {});
            try graph.addChunk(chunk, chunk_position);
            // try loading_chunks.append(self.allocator, chunk);
            const center_chunk_position = observers.zones.get(observer).center_chunk_position;
            const priority = center_chunk_position.sub(chunk_position).mag2();
            try chunks.load_state_events.post(.loading, .{
                .chunk = chunk,
                .priority = priority,
            });
        }
    }

    fn processObserverChunkUnload(self: *Manager, observer: Observer, chunk_position: Vec3i) !void {
        const world = self.world;
        const chunks = &world.chunks;
        const graph = &world.graph;
        const observers = &world.observers;

        // if the chunk already isnt in the graph map, its already unloaded
        const chunk = graph.position_map.get(chunk_position) orelse {
            return;
        };

        const zone = observers.zones.getPtr(observer);
        const load_range = observerZoneRange(zone.center_chunk_position, zone.load_radius);

        if (load_range.contains(chunk_position)) {
            // skip the chunk if its still within the load range of the observer
            return;
        }

        const maps = observers.chunk_maps.get(observer);
        assert(maps.active.contains(chunk) or maps.loading.contains(chunk));
        _ = maps.loading.remove(chunk);
        _ = maps.active.remove(chunk);

        const chunk_status = chunks.statuses.getPtr(chunk);

        chunk_status.mutex.lock();
        defer chunk_status.mutex.unlock();

        if (chunk_status.load_state == .active) {
            const events = observers.chunk_events.get(observer);
            try events.post(.exit, chunk);
        }

        chunk_status.observer_count -= 1;

        if (chunk_status.observer_count > 0) {
            return;
        }

        chunk_status.generation += 1;
        chunk_status.load_state = .unloading;
        self.world.graph.removeChunk(chunk_position);
        try self.unloading_chunks.append(self.allocator, chunk);
        try chunks.load_state_events.post(.unloading, chunk);
    }

    pub fn tick(self: *Manager) !void {
        _ = self;
    }
};

const ChunkLoadJob = struct {
    chunk: Chunk,
    generation: u32,
};

const ChunkLoadJobQueue = util.JobQueueUnmanaged(ChunkLoadJob);

const Loader = struct {
    allocator: Allocator,
    world: *World,

    leko_chunk_loader: *leko.ChunkLoader,

    thread_group: ThreadGroup = undefined,
    is_running: AtomicFlag = .{},

    chunk_load_job_queue: ChunkLoadJobQueue = .{},
    finished_chunks: List(Chunk) = .{},
    finished_chunks_mutex: Mutex = .{},

    fn create(allocator: Allocator, world: *World) !*Loader {
        const self = try allocator.create(Loader);
        self.* = .{
            .allocator = allocator,
            .world = world,
            .leko_chunk_loader = try leko.ChunkLoader.create(allocator, world),
        };
        return self;
    }

    fn destroy(self: *Loader) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.stop();
        self.finished_chunks.deinit(self.allocator);
        self.leko_chunk_loader.destroy();
    }

    fn start(self: *Loader) !void {
        if (self.is_running.get()) {
            @panic("world loader is already running");
        }
        self.is_running.set(true);
        self.thread_group = try ThreadGroup.spawnCpuCount(self.allocator, 0.5, .{}, threadGroupMain, .{self});
    }

    fn stop(self: *Loader) void {
        if (!self.is_running.get()) {
            return;
        }
        self.is_running.set(false);
        self.chunk_load_job_queue.flush(self.allocator);
        self.thread_group.join();
    }

    fn processChunkLoadStateEvents(self: *Loader, finished_chunks: *std.ArrayList(Chunk)) !void {
        for (self.world.chunks.load_state_events.get(.loading)) |event| {
            const generation = self.world.chunks.statuses.get(event.chunk).generation;
            try self.chunk_load_job_queue.push(self.allocator, .{
                .chunk = event.chunk,
                .generation = generation,
            }, event.priority);
        }
        self.finished_chunks_mutex.lock();
        defer self.finished_chunks_mutex.unlock();
        try finished_chunks.appendSlice(self.finished_chunks.items);
        self.finished_chunks.clearRetainingCapacity();
    }

    fn threadGroupMain(self: *Loader) !void {
        const world = self.world;
        const chunks = &world.chunks;
        while (self.is_running.get()) {
            const node = self.chunk_load_job_queue.pop() orelse continue;
            const chunk = node.item.chunk;
            const generation = node.item.generation;
            if (!chunks.tryStartUsingChunk(chunk, generation)) {
                continue;
            }
            defer chunks.stopUsingChunk(chunk);
            try self.loadChunk(chunk);
            self.finished_chunks_mutex.lock();
            defer self.finished_chunks_mutex.unlock();
            try self.finished_chunks.append(self.allocator, chunk);
        }
    }

    fn loadChunk(self: *Loader, chunk: Chunk) !void {
        try self.leko_chunk_loader.loadChunk(chunk);
        // std.time.sleep(20_000_000); // artificial load
    }
};
