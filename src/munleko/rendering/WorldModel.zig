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
    try self.chunk_models.init(allocator);
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
    chunk: Chunk = undefined,
    state: Atomic(ChunkModelState) = .{ .value = .deleted },
};

pub const ChunkModelState = enum(u8) {
    deleted,
    pending,
    ready,
};

const ChunkModelStatusStore = util.IjoDataStoreDefaultInit(ChunkModel, ChunkModelStatus);

const ChunkModels = struct {
    allocator: Allocator,
    pool: ChunkModelPool,
    map: ChunkModelMap = .{},
    map_mutex: Mutex = .{},

    statuses: ChunkModelStatusStore,

    fn init(self: *ChunkModels, allocator: Allocator) !void {
        self.* = .{
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
        status.chunk = chunk;
        status.state.store(.pending, .Monotonic);
        self.map_mutex.lock();
        defer self.map_mutex.unlock();
        try self.map.put(self.allocator, chunk, chunk_model);
        return chunk_model;
    }

    fn deleteAndRemoveChunkModel(self: *ChunkModels, chunk: Chunk) void {
        self.map_mutex.lock();
        defer self.map_mutex.unlock();
        if (self.map.fetchRemove(chunk)) |kv| {
            self.pool.delete(kv.value);
        }
    }

};


pub const Manager = struct {

    pub const ChunkModelJob = struct {
        chunk: Chunk,
        chunk_generation: u32,
        chunk_model: ChunkModel,
        event: Event,

        pub const Event = union(enum) {
            enter: void,
        };
    };

    const ChunkModelJobQueue = util.JobQueueUnmanaged(ChunkModelJob);

    allocator: Allocator,
    world_model: *WorldModel,
    generate_group: ThreadGroup = undefined,
    is_running: AtomicFlag = .{},
    observer: Observer = undefined,

    leko_mesh_system: *LekoMeshSystem,

    chunk_model_job_queue: ChunkModelJobQueue = .{},

    pub fn create(allocator: Allocator, world_model: *WorldModel) !*Manager {
        const self = try allocator.create(Manager);
        self.* = Manager {
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
            self.chunk_model_job_queue.flush(self.allocator);
            self.generate_group.join();
        }
    }

    pub fn onWorldUpdate(self: *Manager, world: *World) !void {
        const model = self.world_model;
        const observer_chunk_events = world.observers.chunk_events.get(self.observer);
        const observer_position = world.observers.zones.get(self.observer).center_chunk_position;
        for(observer_chunk_events.get(.enter)) |chunk| {
            const chunk_model = try model.createAndAddChunkModel(chunk);
            const chunk_position = world.graph.positions.get(chunk);
            const priority = chunk_position.sub(observer_position).mag2();
            const chunk_status = world.chunks.statuses.getPtr(chunk);
            try self.chunk_model_job_queue.push(self.allocator, .{
                .chunk = chunk,
                .chunk_model = chunk_model,
                .chunk_generation = chunk_status.generation,
                .event = .enter,
            }, priority);
        }
        for(observer_chunk_events.get(.exit)) |chunk| {
            model.deleteAndRemoveChunkModel(chunk);
        }
    }

    fn generateThreadMain(self: *Manager) !void {
        const world_model = self.world_model;
        const world = world_model.world;
        while (self.is_running.get()) {
            if (self.chunk_model_job_queue.pop()) |node| {
                const job = node.item;
                const chunk = job.chunk;
                const chunk_model = job.chunk_model;
                const chunk_model_status = world_model.chunk_models.statuses.getPtr(chunk_model);
                if (!world.chunks.tryStartUsingChunk(chunk, job.chunk_generation)) {
                    continue;
                }
                defer world.chunks.stopUsingChunk(chunk);
                try self.leko_mesh_system.processChunkModelJob(job);
                chunk_model_status.state.store(.ready, .Monotonic);
                world_model.dirty_event.set();
            }
        }
    }
};