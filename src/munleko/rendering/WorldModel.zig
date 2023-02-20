const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Atomic = std.atomic.Atomic;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ThreadGroup = util.ThreadGroup;
const AtomicFlag = util.AtomicFlag;
const ResetEvent = Thread.ResetEvent;

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const leko_mesh = @import("leko_mesh.zig");
const ChunkLekoMeshes = leko_mesh.ChunkLekoMeshes;
const LekoMeshSystem = leko_mesh.LekoMeshSystem;

const Session = Engine.Session;
const World = Engine.World;
const Chunk = World.Chunk;
const Observer = World.Observer;

const Allocator = std.mem.Allocator;
const WorldModel = @This();

const Vec3 = nm.Vec3;

pub const chunk_model_bounds_radius = std.math.sqrt(3) * World.chunk_width;

allocator: Allocator,
world: *World,
chunk_models: ChunkModels = undefined,
chunk_leko_meshes: ChunkLekoMeshes = undefined,
dirty_event: ResetEvent = .{},

pub fn create(allocator: Allocator, world: *World) !*WorldModel {
    const self = try allocator.create(WorldModel);
    self.* = WorldModel{
        .allocator = allocator,
        .world = world,
    };
    try self.chunk_models.init(self);
    try self.chunk_leko_meshes.init(allocator);
    return self;
}

pub fn destroy(self: *WorldModel) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.chunk_models.deinit();
    self.chunk_leko_meshes.deinit();
}

fn createAndAddChunkModel(self: *WorldModel, chunk: Chunk) !ChunkModel {
    const chunk_model = try self.chunk_models.createAndAddChunkModel(chunk);
    try self.chunk_leko_meshes.matchDataCapacity(self);
    return chunk_model;
}

fn deleteAndRemoveChunkModel(self: *WorldModel, chunk: Chunk) void {
    self.chunk_models.deleteAndRemoveChunkModel(chunk);
}

pub const ChunkModel = util.Ijo("world chunk model");
const ChunkModelMap = std.HashMapUnmanaged(Chunk, ChunkModel, Chunk.HashContext, std.hash_map.default_max_load_percentage);

const ChunkModelPool = util.IjoPool(ChunkModel);

pub const ChunkModelStatus = struct {
    mutex: Mutex = .{},
    chunk: Chunk = undefined,
    state: ChunkModelState = .deleted,
    generation: u32 = 0,
    chunk_generation: u32 = 0,
    task_flags: ChunkModelTaskFlags = ChunkModelTaskFlags.initEmpty(),
    is_busy: bool = false,
};

pub const ChunkModelState = enum(u8) {
    deleted,
    pending,
    ready,
};

pub const ChunkModelTask = enum {
    leko_mesh_generate_middle,
    leko_mesh_generate_border,
};

pub const ChunkModelTaskFlags = std.enums.EnumSet(ChunkModelTask);

fn initChunkModelTaskFlagsFromSet(set: []const ChunkModelTask) ChunkModelTaskFlags {
    var flags = ChunkModelTaskFlags.initEmpty();
    for (set) |flag| {
        flags.insert(flag);
    }
    return flags;
}

const ChunkModelStatusStore = util.IjoDataStoreDefaultInit(ChunkModel, ChunkModelStatus);

const ChunkModels = struct {
    world_model: *WorldModel,
    allocator: Allocator,
    pool: ChunkModelPool,
    map: ChunkModelMap = .{},
    map_mutex: Mutex = .{},

    statuses: ChunkModelStatusStore,

    fn init(self: *ChunkModels, world_model: *WorldModel) !void {
        const allocator = world_model.allocator;
        self.* = .{
            .world_model = world_model,
            .allocator = allocator,
            .pool = ChunkModelPool.init(allocator),
            .statuses = ChunkModelStatusStore.init(allocator),
        };
    }

    fn deinit(self: *ChunkModels) void {
        self.pool.deinit();
        self.map.deinit(self.allocator);
        self.statuses.deinit();
    }

    fn createAndAddChunkModel(self: *ChunkModels, chunk: Chunk) !ChunkModel {
        const chunk_model = try self.pool.create();
        try self.statuses.matchCapacity(self.pool);
        const status = self.statuses.getPtr(chunk_model);
        status.mutex.lock();
        status.mutex.unlock();
        status.chunk = chunk;
        const chunk_status = self.world_model.world.chunks.statuses.getPtr(chunk);
        status.state = .pending;
        status.chunk_generation = chunk_status.generation;
        status.task_flags = ChunkModelTaskFlags.initEmpty();
        status.is_busy = false;
        self.map_mutex.lock();
        defer self.map_mutex.unlock();
        try self.map.put(self.allocator, chunk, chunk_model);
        return chunk_model;
    }

    fn deleteAndRemoveChunkModel(self: *ChunkModels, chunk: Chunk) void {
        self.map_mutex.lock();
        defer self.map_mutex.unlock();
        if (self.map.fetchRemove(chunk)) |kv| {
            const chunk_model = kv.value;
            self.pool.delete(chunk_model);
            const status = self.statuses.getPtr(chunk_model);
            status.mutex.lock();
            defer status.mutex.unlock();
            status.generation +%= 1;
        }
    }
};


pub const Manager = struct {
    allocator: Allocator,
    world_model: *WorldModel,
    generate_group: ThreadGroup = undefined,
    is_running: AtomicFlag = .{},
    observer: Observer = undefined,

    leko_mesh_system: *LekoMeshSystem,

    job_queue: ChunkModelJobQueue = .{},
    job_queue_mutex: Mutex = .{},
    job_queue_condition: std.Thread.Condition = .{},

    const ChunkModelJobQueue = util.HeapUnmanaged(ChunkModelQueueItem, (struct {
        fn before(a: ChunkModelQueueItem, b: ChunkModelQueueItem) bool {
            return a.priority < b.priority;
        }
    }).before);

    const ChunkModelQueueItem = struct {
        chunk_model: ChunkModel,
        generation: u32,
        priority: i32,
    };

    pub const ChunkModelJob = struct {
        chunk: Chunk,
        chunk_model: ChunkModel,
        task_flags: ChunkModelTaskFlags,
    };

    pub fn create(allocator: Allocator, world_model: *WorldModel) !*Manager {
        const self = try allocator.create(Manager);
        self.* = Manager{
            .allocator = allocator,
            .world_model = world_model,
            .leko_mesh_system = try LekoMeshSystem.create(allocator, world_model),
        };
        return self;
    }

    pub fn destroy(self: *Manager) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.stop();
        self.leko_mesh_system.destroy();
        self.job_queue.deinit(self.allocator);
    }

    pub fn start(self: *Manager, observer: Observer) !void {
        if (self.is_running.get()) {
            @panic("world model manager already running");
        }
        self.observer = observer;
        self.is_running.set(true);
        self.generate_group = try ThreadGroup.spawnCpuCount(self.allocator, 0.5, .{}, generateThreadMain, .{self});
    }

    pub fn stop(self: *Manager) void {
        if (self.is_running.get()) {
            self.is_running.set(false);
            // self.job_queue_condition.broadcast();
            self.flushJobQueue();
            self.generate_group.join();
        }
    }

    pub fn onWorldUpdate(self: *Manager, world: *World) !void {
        const model = self.world_model;
        const observer_chunk_events = world.observers.chunk_events.get(self.observer);
        const observer_position = world.observers.zones.get(self.observer).center_chunk_position;
        for (observer_chunk_events.get(.enter)) |chunk| {
            const chunk_model = try model.createAndAddChunkModel(chunk);
            const chunk_position = world.graph.positions.get(chunk);
            const priority = chunk_position.sub(observer_position).mag2();

            try self.setTaskFlags(chunk_model, priority, &.{ .leko_mesh_generate_middle, .leko_mesh_generate_border });
            var neighbor_range_iter = nm.Range3i.init(
                chunk_position.subScalar(1).v,
                chunk_position.addScalar(2).v,
            ).iterate();
            while (neighbor_range_iter.next()) |neighbor_position| {
                if (neighbor_position.eql(chunk_position)) {
                    continue;
                }
                const neighbor_chunk = world.graph.position_map.get(neighbor_position) orelse continue;
                const neighbor_chunk_model = model.chunk_models.map.get(neighbor_chunk) orelse continue;
                // const neighbor_chunk_generation = world.chunks.statuses.get(neighbor_chunk).generation;
                const neighbor_priority = neighbor_position.sub(observer_position).mag2();
                try self.setTaskFlags(neighbor_chunk_model, neighbor_priority, &.{.leko_mesh_generate_border});
            }
        }
        for (observer_chunk_events.get(.exit)) |chunk| {
            model.deleteAndRemoveChunkModel(chunk);
        }
    }

    fn generateThreadMain(self: *Manager) !void {
        const world_model = self.world_model;
        const world = world_model.world;
        self.job_queue_mutex.lock();
        defer self.job_queue_mutex.unlock();
        while (self.waitForNextAvailableJob()) |job| {
            defer self.finishJob(job.chunk_model);
            self.job_queue_mutex.unlock();
            defer self.job_queue_mutex.lock();
            world.chunks.startUsingChunk(job.chunk);
            defer world.chunks.stopUsingChunk(job.chunk);
            try self.leko_mesh_system.processChunkModelJob(job);
        }
    }

    fn flushJobQueue(self: *Manager) void {
        self.job_queue_mutex.lock();
        defer self.job_queue_mutex.unlock();
        self.job_queue.items.clearRetainingCapacity();
        self.job_queue_condition.broadcast();
    }

    fn setTaskFlags(self: *Manager, chunk_model: ChunkModel, priority: i32, comptime flag_set: []const ChunkModelTask) !void {
        self.job_queue_mutex.lock();
        defer self.job_queue_mutex.unlock();
        const status = self.world_model.chunk_models.statuses.getPtr(chunk_model);
        status.mutex.lock();
        defer status.mutex.unlock();
        const flags = comptime initChunkModelTaskFlagsFromSet(flag_set);
        const old_flags = status.task_flags;
        status.task_flags.setUnion(flags);
        if (old_flags.count() == 0) {
            try self.job_queue.push(self.allocator, .{
                .chunk_model = chunk_model,
                .generation = status.generation,
                .priority = priority,
            });
            self.job_queue_condition.signal();
        }
    }

    fn waitForNextAvailableJob(self: *Manager) ?ChunkModelJob {
        // self.job_queue_mutex.lock();
        // defer self.job_queue_mutex.unlock();
        while (self.is_running.get()) {
            if (self.getNextAvailableJob()) |job| {
                return job;
            }
            self.job_queue_condition.wait(&self.job_queue_mutex);
        }
        return null;
    }

    fn getNextAvailableJob(self: *Manager) ?ChunkModelJob {
        var i: usize = 0;
        while (i < self.job_queue.items.items.len) {
            const item = self.job_queue.items.items[i];
            const chunk_model = item.chunk_model;
            const status = self.world_model.chunk_models.statuses.getPtr(chunk_model);
            status.mutex.lock();
            defer status.mutex.unlock();
            if (status.generation != item.generation) {
                _ = self.job_queue.popAtIndex(i);
                continue;
            }
            if (status.is_busy) {
                i += 1;
                continue;
            }
            const flags = status.task_flags;
            status.task_flags = ChunkModelTaskFlags.initEmpty();
            status.is_busy = true;
            _ = self.job_queue.popAtIndex(i);
            return ChunkModelJob{
                .chunk = status.chunk,
                .chunk_model = chunk_model,
                .task_flags = flags,
            };
        }
        return null;
    }

    fn finishJob(self: *Manager, chunk_model: ChunkModel) void {
        // self.job_queue_mutex.lock();
        // defer self.job_queue_mutex.unlock();
        defer self.world_model.dirty_event.set();
        const status = self.world_model.chunk_models.statuses.getPtr(chunk_model);
        status.mutex.lock();
        defer status.mutex.unlock();
        status.is_busy = false;
        status.state = .ready;
        if (status.task_flags.count() != 0) {
            self.job_queue_condition.signal();
        }
    }
};
