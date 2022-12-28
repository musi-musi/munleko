const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Atomic = std.atomic.Atomic;
const Thread = std.Thread;
const ThreadGroup = util.ThreadGroup;

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

pub const ChunkModel = util.Ijo("world chunk model");
const ChunkModelMap = std.HashMapUnmanaged(Chunk, ChunkModel, Chunk.HashContext, std.hash_map.default_max_load_percentage);

const ChunkModelPool = util.IjoPool(ChunkModel);

const ChunkModels = struct {
    allocator: Allocator,
    pool: ChunkModelPool,
    map: ChunkModelMap = .{},

    fn init(self: *ChunkModels, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .pool = ChunkModelPool.init(allocator),
        };
    }

    fn deinit(self: *ChunkModels) void {
        self.pool.deinit();
        self.map.deinit(self.allocator);
    }

};

pub const Manager = struct {

    allocator: Allocator,
    world_model: *WorldModel,
    generate_group: ThreadGroup = undefined,
    is_running: Atomic(bool) = .{ .value = false, },
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
        if (self.is_running.load(.Monotonic)) {
            @panic("world model manager already running");
        }
        self.observer = observer;
        self.is_running.store(true, .Monotonic);
        self.generate_group = try ThreadGroup.spawnCpuCount(self.allocator, 0.5, .{}, generateThreadMain, .{self});
    }

    pub fn stop(self: *Manager) void {
        if (self.is_running.load(.Monotonic)) {
            self.is_running.store(false, .Monotonic);
            self.generate_group.join();
        }
    }

    pub fn onWorldUpdate(self: *Manager, world: *World) !void {
        const observer_chunk_events = &world.observers.statuses.getPtr(self.observer).chunk_events;
        for(observer_chunk_events.get(.enter)) |event| {
            _ = event;
        }
        for(observer_chunk_events.get(.exit)) |event| {
            _ = event;
        }
    }

    fn generateThreadMain(self: *Manager) !void {
        while (self.is_running.load(.Monotonic)) {

        }
    }
};