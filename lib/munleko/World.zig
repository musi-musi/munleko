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

const Range3i = nm.Range3i;

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
    active,
    unloading,
};

pub const ChunkStatus = struct {
    load_state: ChunkLoadState = .deleted,
    pending_load_state: ?ChunkLoadState = null,
    user_count: u32 = 0,
    observer_count: u32 = 0,
    mutex: Mutex = .{},
    index: usize = 0,
};

pub const ChunkLoadStateEvents = util.Events(union(ChunkLoadState) {
    deleted: Chunk,
    loading: PriorityChunk,
    active: Chunk,
    unloading: Chunk,
});

pub const PriorityChunk = struct {
    chunk: Chunk,
    priority: i32,
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
    chunk_list: List(Chunk) = .{},

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
        self.chunk_list.deinit(self.allocator);
    }

    pub fn startUsing(self: *Chunks, chunk: Chunk) void {
        assertOnWorldUpdateThread();
        self.statuses.getPtr(chunk).user_count += 1;
    }

    pub fn stopUsing(self: *Chunks, chunk: Chunk) void {
        assertOnWorldUpdateThread();
        self.statuses.getPtr(chunk).user_count -= 1;
    }

    fn create(self: *Chunks) !Chunk {
        const chunk = try self.pool.create();
        try self.statuses.matchCapacity(self.pool);
        self.statuses.getPtr(chunk).index = self.chunk_list.items.len;
        try self.chunk_list.append(self.allocator, chunk);
        return chunk;
    }

    fn delete(self: *Chunks, chunk: Chunk) void {
        const index = self.statuses.get(chunk).index;
        _ = self.chunk_list.swapRemove(index);
        if (index != self.chunk_list.items.len) {
            self.statuses.getPtr(self.chunk_list.items[index]).index = index;
        }
    }

};

pub fn chunkPositionToCenterPosition(chunk_position: Vec3i) Vec3i {
    return chunk_position.mulScalar(chunk_width);
}

fn createAndAddChunk(self: *World, position: Vec3i) !Chunk {
    const graph = &self.graph;
    const chunk = try self.chunks.create();
    try graph.matchDataCapacity(self.chunks.pool);
    try self.graph.addChunk(chunk, position);
    return chunk;
}

pub const ChunkPositionStore = util.IjoDataStoreValueInit(Chunk, Vec3i, Vec3i.zero);

pub const Graph = struct {

    allocator: Allocator,
    positions: ChunkPositionStore,
    position_map: PositionMap(Chunk) = .{},

    position_map_mutex: Mutex = .{},

    fn init(self: *Graph, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .positions = ChunkPositionStore.init(allocator),
        };
    }

    fn deinit(self: *Graph) void {
        const allocator = self.allocator;
        self.positions.deinit();
        self.position_map.deinit(allocator);
    }

    fn matchDataCapacity(self: *Graph, pool: ChunkPool) !void {
        try self.positions.matchCapacity(pool);
    }

    fn addChunk(self: *Graph, chunk: Chunk, position: Vec3i) !void {
        self.positions.getPtr(chunk).* = position;
        self.position_map_mutex.lock();
        defer self.position_map_mutex.unlock();
        try self.position_map.put(self.allocator, position, chunk);
    }

    fn removeChunk(self: *Graph, chunk: Chunk) void {
        self.position_map_mutex.lock();
        defer self.position_map_mutex.unlock();
        _ =  self.position_map.remove(self.positions.get(chunk));
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

pub const ObserverZone = struct {
    mutex: Mutex = .{},
    position: Vec3i = Vec3i.zero,
    center_chunk_position: Vec3i = Vec3i.zero,
    load_radius: u32 = 4,

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
        self.center_chunk_position = self.position.cast(f32).divScalar(chunk_width).round().cast(i32);
        return .{
            .old = old_center_position,
            .new = self.center_chunk_position,
        };
    }


    /// given two center chunk positions and a radius, return the result of the set operation a / b
    /// the difference is represented as up to 3 non-intersecting ranges in the given array
    pub fn subtractZones(center_a: Vec3i, center_b: Vec3i, load_radius: u32, ranges: *[3]Range3i) []Range3i {
        var count: u32 = 0;
        var range = @ptrCast([*]Range3i.Comp, ranges);
        const d = @bitCast(Vec3i.Comp, center_b.sub(center_a));
        const b = @bitCast(Vec3i.Comp, center_b);
        const a = @bitCast(Vec3i.Comp, center_a);
        const r = @intCast(i32, load_radius);
        const r2 = r * 2;
        // special case: if zone a and b dont intersect, the difference is just zone a
        if (abs(d.x) >= r2 or abs(d.y) >= r2 or abs(d.z) >= r2) {
            ranges.*[0].min = center_a.subScalar(r);
            ranges.*[0].max = center_a.addScalar(r);
            return ranges[0..1];
        }
        if (d.x != 0) {
            if (d.x < 0) {
                range[0].min.x = b.x + r;
                range[0].max.x = a.x + r;
            }
            else {
                range[0].min.x = a.x - r;
                range[0].max.x = b.x - r;
            }
            range[0].min.y = a.y - r;
            range[0].min.z = a.z - r;
            range[0].max.y = a.y + r;
            range[0].max.z = a.z + r;
            range += 1;
            count += 1;
        }
        if (d.y != 0) {
            if (d.x < 0) {
                range[0].min.x = a.x - r;
                range[0].max.x = b.x + r;
            }
            else {
                range[0].min.x = b.x - r;
                range[0].max.x = a.x + r;
            }
            if (d.y < 0) {
                range[0].min.y = b.y + r;
                range[0].max.y = a.y + r;
            }
            else {
                range[0].min.y = a.y - r;
                range[0].max.y = b.y - r;
            }
            range[0].min.z = a.z - r;
            range[0].max.z = a.z + r;
            range += 1;
            count += 1;
        }
        if (d.z != 0) {
            if (d.x < 0) {
                range[0].min.x = a.x - r;
                range[0].max.x = b.x + r;
            }
            else {
                range[0].min.x = b.x - r;
                range[0].max.x = a.x + r;
            }
            if (d.y < 0) {
                range[0].min.y = a.y - r;
                range[0].max.y = b.y + r;
            }
            else {
                range[0].min.y = b.y - r;
                range[0].max.y = a.y + r;
            }
            if (d.z < 0) {
                range[0].min.z = b.z + r;
                range[0].max.z = a.z + r;
            }
            else {
                range[0].min.z = a.z - r;
                range[0].max.z = b.z - r;
            }
            range += 1;
            count += 1;
        }
        return ranges.*[0..count];
    }

    fn abs(x: i32) i32 {
        if (x < 0) {
            return -x;
        }
        else {
            return x;
        }
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
        self.statuses.getPtr(observer).is_dirty.store(true, .Monotonic);
        // const load_center_position = zone.center_chunk_position.divFloorScalar(chunk_width);
        // if (position.sub(load_center_position).mag2() > chunk_width * chunk_width) {
        // }
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

    fn swapRemove(self: *Observers, i: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.observer_list.swapRemove(i);
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
    range_load_events: RangeLoadEvents,

    const RangeLoadEvents = util.Events(union(enum) {
        load: RangeLoadEvent,
        unload: RangeLoadEvent,
    });

    const RangeLoadEvent = struct {
        observer: Observer,
        range: Range3i,
    };

    pub fn OnWorldUpdateFn(comptime Context: type) type {
        return fn(Context, *World) anyerror!void;
    }

    pub fn create(allocator: Allocator, world: *World) !*Manager {
        const self = try allocator.create(Manager);
        self.* = .{
            .allocator = allocator,
            .world = world,
            .range_load_events = RangeLoadEvents.init(allocator),
        };
        return self;
    }

    pub fn destroy(self: *Manager) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.stop();
        self.pending_chunks.deinit(allocator);
        self.range_load_events.deinit();
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

            self.range_load_events.clearAll();

            // self.checkChunks();

            try self.processPendingChunks();
            try self.processDirtyObservers();
            try self.processRangeLoadEvents();

            try on_update_fn(context, self.world);

            self.world.chunks.load_state_events.clearAll();
        }
    }

    fn checkChunks(self: Manager) void {
        if (std.debug.runtime_safety) {
            const world = self.world;
            const chunks = &world.chunks;
            const graph = &world.graph;
            for (chunks.chunk_list.items) |chunk| {
                const status = chunks.statuses.get(chunk);
                // const count = std.mem.count(Chunk, self.pending_chunks.items, &[1]Chunk{chunk});
                // if (status.pending_load_state) |_| {
                //     std.debug.assert(count == 1);
                // }
                // else {
                //     std.debug.assert(count == 0);
                // }
                const position = graph.positions.get(chunk);
                const load_state = status.load_state;
                if (load_state == .loading) {
                    const mapped_chunk = graph.position_map.get(position);
                    std.debug.assert(mapped_chunk != null);
                    std.debug.assert(mapped_chunk == chunk);
                }
                if (load_state == .active) {
                    const mapped_chunk = graph.position_map.get(position);
                    std.debug.assert(mapped_chunk != null);
                    std.debug.assert(mapped_chunk == chunk);
                }
            }
        }
    }

    fn processPendingChunks(self: *Manager) !void {
        const world = self.world;
        const chunks = &world.chunks;
        var i: usize = 0;
        while (i < self.pending_chunks.items.len) {
            const chunk = self.pending_chunks.items[i];
            const status = chunks.statuses.getPtr(chunk);
            if (status.user_count != 0) {
                // dont process chunks that are still being used by external systems
                i += 1;
                continue;
            }
            const pending_state = status.pending_load_state.?;
            status.load_state = pending_state;
            switch (pending_state) {
                // chunks only become .loading from startChunkLoad, which handles load state events in that case
                .loading => unreachable,
                inline else => |state| {
                    try chunks.load_state_events.post(state, chunk);
                }
            }
            if (status.load_state == .active) {
                status.pending_load_state = null;
            }
            else {
                // the graph only holds chunks that are active or loading
                // chunks cannot become loading from the pending list, so we dont need to check 
                // for .loading
                world.graph.removeChunk(chunk);
            }
            switch (status.load_state) {
                .unloading => {
                    // chunks that are now unloading are immediately queued for deletion
                    status.pending_load_state = .deleted;
                },
                .deleted => {
                    // chunks that are now deleted must be. well. deleted
                    status.pending_load_state = null;
                    chunks.delete(chunk);
                },
                else => {},
            }
            if (status.pending_load_state != null) {
                // if the chunk does not have a pending state after processing, we dont need to remove it
                i += 1;
                continue;
            }
            _ = self.pending_chunks.swapRemove(i);
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
                    try self.range_load_events.post(.load, .{
                        .observer = observer,
                        .range = .{
                            .min = center_position.subScalar(@intCast(i32, zone.load_radius)),
                            .max = center_position.addScalar(@intCast(i32, zone.load_radius)),
                        }
                    });
                },
                .active => {
                    const center_position = zone.updateCenterChunkPosition();
                    var ranges: [3]Range3i = undefined;
                    const load_ranges = ObserverZone.subtractZones(center_position.new, center_position.old, zone.load_radius, &ranges);
                    for (load_ranges) |range| {
                        try self.range_load_events.post(.load, .{
                            .observer = observer,
                            .range = range,
                        });
                    }
                    const unload_ranges = ObserverZone.subtractZones(center_position.old, center_position.new, zone.load_radius, &ranges);
                    for (unload_ranges) |range| {
                        try self.range_load_events.post(.unload, .{
                            .observer = observer,
                            .range = range,
                        });
                    }
                },
                .deleting => {
                    const center_position = zone.center_chunk_position;
                    try self.range_load_events.post(.unload, .{
                        .observer = observer,
                        .range = .{
                            .min = center_position.subScalar(@intCast(i32, zone.load_radius)),
                            .max = center_position.addScalar(@intCast(i32, zone.load_radius)),
                        }
                    });
                    status.state.store(.deleted, .Monotonic);
                    observers.swapRemove(i);
                },
            }
        }
    }

    fn processRangeLoadEvents(self: *Manager) !void {
        const world = self.world;
        const observers = &world.observers;
        for (self.range_load_events.get(.load)) |event| {
            var iter = event.range.iterate();
            while (iter.next()) |position| {
                try self.startChunkLoad(position, event.observer);
            }
        }
        for (self.range_load_events.get(.unload)) |event| {
            var iter = event.range.iterate();
            while (iter.next()) |position| {
                try self.startChunkUnload(position, event.observer);
            }
            const status = observers.statuses.getPtr(event.observer);
            if (status.state.load(.Monotonic) == .deleted) {
                observers.mutex.lock();
                defer observers.mutex.unlock();
                observers.pool.delete(event.observer);
            }
        }
    }

    fn startChunkLoad(self: *Manager, position: Vec3i, observer: Observer) !void {
        const world = self.world;
        const chunks = &world.chunks;
        const graph = &world.graph;
        const observers = &world.observers;
        if (graph.position_map.get(position)) |chunk| {
            const status = chunks.statuses.getPtr(chunk);
            std.debug.assert(status.load_state == .active or status.load_state == .loading);
            status.observer_count += 1;
            if (status.observer_count > 1) {
                std.log.info("count {d}", .{status.observer_count});
            }
        }
        else {
            const chunk = try world.createAndAddChunk(position);
            const status = chunks.statuses.getPtr(chunk);
            status.observer_count = 1;
            status.load_state = .loading;
            status.pending_load_state = .active;
            status.user_count = 0;
            try chunks.load_state_events.post(.loading, .{
                .chunk = chunk,
                .priority = (
                    observers.zones.get(observer)
                    .center_chunk_position
                    .sub(position).mag2()
                ),
            });
            try self.pending_chunks.append(self.allocator, chunk);
        }
    }

    fn startChunkUnload(self: *Manager, position: Vec3i, observer: Observer) !void {
        _ = observer;
        const world = self.world;
        const chunks = &world.chunks;
        const graph = &world.graph;
        const chunk = graph.position_map.get(position) orelse {
            return;
        };
        const status = chunks.statuses.getPtr(chunk);
        status.observer_count -= 1;
        if (status.observer_count != 0) {
            return;
        }
        if (status.pending_load_state == null) {
            // if the chunks isnt already pending, it needs to be added to the list of pending chunks
            try self.pending_chunks.append(self.allocator, chunk);
        }
        status.pending_load_state = .unloading;
    }

    pub fn tick(self: *Manager) !void {
        _ = self;
    }
};