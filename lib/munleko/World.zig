const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Engine = @import("Engine.zig");
const Session = @import("Session.zig");
const leko = @import("leko.zig");

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
leko: leko.LekoData = undefined,

pub const ChunkLoadState = enum {
    deleted,
    loading,
    active,
    unloading,
};

pub const ChunkStatus = struct {
    load_state: ChunkLoadState = .deleted,
    pending_load_state: ?ChunkLoadState = null,
    user_count: Atomic(u32) = .{ .value = 0, },
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
    try self.leko.init(allocator);
    return self;

}

pub fn destroy(self: *World) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);

    self.chunks.deinit();
    self.observers.deinit();
    self.graph.deinit();
    self.leko.deinit();

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
        _ = self.statuses.getPtr(chunk).user_count.fetchAdd(1, .Monotonic);
    }

    pub fn stopUsing(self: *Chunks, chunk: Chunk) void {
        _ = self.statuses.getPtr(chunk).user_count.fetchSub(1, .Monotonic);
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
        self.pool.delete(chunk);
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

    fn rangeForZone(center: Vec3i, load_radius: u32) Range3i {
        return Range3i.init(
            center.subScalar(@intCast(i32, load_radius)).v,
            center.addScalar(@intCast(i32, load_radius)).v,
        );
    }

    pub fn observerdRange(self: ObserverZone) Range3i {
        return rangeForZone(self.center_chunk_position, self.load_radius);
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
    chunk_events: ObserverChunkEvents,
    waiting_chunks: std.ArrayList(Chunk),
};

const ObserverChunkEvents = util.Events(union(enum) {
    enter: Chunk,
    exit: Chunk,
});

const ObserverZoneStore = util.IjoDataStoreDefaultInit(Observer, ObserverZone);
const ObserverStatusStore = util.IjoDataStore(Observer, ObserverStatus, struct {
    pub fn initData(_: @This(), arena: *std.heap.ArenaAllocator) !ObserverStatus {
        return ObserverStatus {
            .chunk_events = ObserverChunkEvents.init(arena.child_allocator),
            .waiting_chunks = std.ArrayList(Chunk).init(arena.child_allocator),
        };
    }
    pub fn deinitData(_: @This(), status: *ObserverStatus) void {
        status.chunk_events.deinit();
        status.waiting_chunks.deinit();
    }
});
const ObserverEventsStore = util.IjoEventsStore(Observer, );
const ObserverPendingListStore = util.IjoDataListStore(Observer, Chunk);

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

        self.observer_list.deinit(allocator);

        self.pool.deinit();
        self.zones.deinit();
        self.statuses.deinit();

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

    leko_load_system: *leko.LekoLoadSystem,

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
            .leko_load_system = try leko.LekoLoadSystem.create(allocator),
        };
        return self;
    }

    pub fn destroy(self: *Manager) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.stop();
        self.pending_chunks.deinit(allocator);
        self.range_load_events.deinit();
        self.leko_load_system.destroy();
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
        try self.leko_load_system.start(self.world);
    }

    pub fn stop(self: *Manager) void {
        if (self.thread_is_running.load(.Monotonic)) {
            self.leko_load_system.stop();
            self.thread_is_running.store(false, .Monotonic);
            self.update_thread.join();
        }
    }

    fn threadMain(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        on_world_update_thread = true;
        while (self.thread_is_running.load(.Monotonic)) {

            self.range_load_events.clearAll();


            try self.processPendingChunks();
            // self.checkChunks();
            try self.processDirtyObservers();
            try self.processRangeLoadEvents();

            try self.leko_load_system.onWorldUpdate(self.world);

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
            if (status.user_count.load(.Monotonic) != 0) {
                // dont process chunks that are still being used by external systems
                i += 1;
                continue;
            }
            const pending_state = status.pending_load_state.?;
            status.load_state = pending_state;
            switch (status.load_state) {
                // chunks only become .loading from startChunkLoad, which handles load state events in that case
                .loading => unreachable,
                inline else => |state| {
                    try chunks.load_state_events.post(state, chunk);
                }
            }
            if (status.load_state == .active) {
                status.pending_load_state = null;
            }
            switch (status.load_state) {
                .unloading => {
                    // chunks that are now unloading are immediately queued for deletion
                    status.pending_load_state = .deleted;
                    world.graph.removeChunk(chunk);
                },
                .deleted => {
                    // chunks that are now deleted must be. well. deleted
                    status.pending_load_state = null;
                    chunks.delete(chunk);
                },
                else => {},
            }
            if (status.pending_load_state != null) {
                // if the chunk does still has a pending state after processing, we dont need to remove it
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
                    try self.processObserverWaitingChunks(observer);
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
                    status.chunk_events.clearAll();
                    status.waiting_chunks.clearRetainingCapacity();
                    observers.swapRemove(i);
                },
            }
        }
    }

    fn processObserverWaitingChunks(self: *Manager, observer: Observer) !void {
        const world = self.world;
        const chunks = &world.chunks;
        const graph = &world.graph;
        const status = world.observers.statuses.getPtr(observer);
        const zone = world.observers.zones.getPtr(observer);
        const range = zone.observerdRange();
        status.chunk_events.clearAll();
        var i: usize = 0;
        while (i < status.waiting_chunks.items.len) {
            const chunk = status.waiting_chunks.items[i];
            const chunk_position = graph.positions.get(chunk);
            const chunk_status = chunks.statuses.get(chunk);
            if (!range.contains(chunk_position)) {
                _ = status.waiting_chunks.swapRemove(i);
                continue;
            }
            switch (chunk_status.load_state) {
                .deleted => unreachable,
                .loading => {
                    i += 1;
                },
                .active => {
                    try status.chunk_events.post(.enter, chunk);
                    _ = status.waiting_chunks.swapRemove(i);
                },
                .unloading => {
                    _ = status.waiting_chunks.swapRemove(i);
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
        const observer_status = observers.statuses.getPtr(observer);
        if (graph.position_map.get(position)) |chunk| {
            const status = chunks.statuses.getPtr(chunk);
            status.observer_count += 1;
            if (status.observer_count > 1) {
                std.log.info("count {d}", .{status.observer_count});
            }
            switch (status.load_state) {
                .active => try observer_status.chunk_events.post(.enter, chunk),
                .loading => try observer_status.waiting_chunks.append(chunk),
                else => unreachable,
            }
            if (status.pending_load_state != null and status.load_state == .loading) {
                status.pending_load_state = .active;
            }
        }
        else {
            const chunk = try world.createAndAddChunk(position);
            const status = chunks.statuses.getPtr(chunk);
            status.observer_count = 1;
            status.load_state = .loading;
            status.pending_load_state = .active;
            status.user_count.store(0, .Monotonic);
            try chunks.load_state_events.post(.loading, .{
                .chunk = chunk,
                .priority = (
                    observers.zones.get(observer)
                    .center_chunk_position
                    .sub(position).mag2()
                ),
            });
            try self.pending_chunks.append(self.allocator, chunk);
            try observer_status.waiting_chunks.append(chunk);
        }
    }

    fn startChunkUnload(self: *Manager, position: Vec3i, observer: Observer) !void {
        const world = self.world;
        const chunks = &world.chunks;
        const graph = &world.graph;
        const observers = &world.observers;
        const chunk = graph.position_map.get(position) orelse {
            return;
        };
        const status = chunks.statuses.getPtr(chunk);
        status.observer_count -= 1;
        const observer_status = observers.statuses.getPtr(observer);
        if (observer_status.state.load(.Monotonic) == .active) {
            try observer_status.chunk_events.post(.exit, chunk);
        }
        if (status.observer_count != 0) {
            return;
        }
        if (status.pending_load_state == null) {
            // if the chunks isnt already pending, it needs to be added to the list of pending chunks
            try self.pending_chunks.append(self.allocator, chunk);
        }
        // if (status.load_state == .loading) {
        //     graph.removeChunk(chunk);
        // }
        status.pending_load_state = .unloading;
    }

    pub fn tick(self: *Manager) !void {
        _ = self;
    }
};