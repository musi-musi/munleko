const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Atomic = std.atomic.Atomic;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ThreadGroup = util.ThreadGroup;
const AtomicFlag = util.AtomicFlag;

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;
const World = Engine.World;
const Chunk = World.Chunk;
const Observer = World.Observer;

const Allocator = std.mem.Allocator;

const WorldModel = @This();

allocator: Allocator,
world: *World,
chunk_models: ChunkModels = undefined,

pub fn create(allocator: Allocator, world: *World) !*WorldModel {
    const self = try allocator.create(WorldModel);
    self.* = WorldModel{
        .allocator = allocator,
        .world = world,
    };
    try self.chunk_models.init(allocator);
    return self;
}

pub fn destroy(self: *WorldModel) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.chunk_models.deinit();
}

fn createAndAddChunkModel(self: *WorldModel, chunk: Chunk) !ChunkModel {
    const chunk_model = try self.chunk_models.createAndAddChunkModel(chunk);
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
        self.statuses.getPtr(chunk_model).chunk = chunk;
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

    allocator: Allocator,
    world_model: *WorldModel,
    generate_group: ThreadGroup = undefined,
    is_running: AtomicFlag = .{},
    observer: Observer = undefined,

    pub fn create(allocator: Allocator, world_model: *WorldModel) !*Manager {
        const self = try allocator.create(Manager);
        self.* = Manager{
            .allocator = allocator,
            .world_model = world_model,
        };
        return self;
    }

    pub fn destroy(self: *Manager) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.stop();
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
            self.generate_group.join();
        }
    }

    pub fn onWorldUpdate(self: *Manager, world: *World) !void {
        const model = self.world_model;
        const chunk_models = &self.world_model.chunk_models;
        const observer_chunk_events = &world.observers.statuses.getPtr(self.observer).chunk_events;
        for(observer_chunk_events.get(.enter)) |chunk| {
            if (chunk_models.map.contains(chunk)) {
                continue;
            }
            const chunk_model = try model.createAndAddChunkModel(chunk);
            _ = chunk_model;
        }
        for(observer_chunk_events.get(.exit)) |chunk| {
            model.deleteAndRemoveChunkModel(chunk);
        }
    }

    fn generateThreadMain(self: *Manager) !void {
        while (self.is_running.get()) {

        }
    }
};