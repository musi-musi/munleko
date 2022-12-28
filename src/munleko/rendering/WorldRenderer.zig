const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;
const World = Engine.World;
const Chunk = World.Chunk;
const Observer = World.Observer;

const WorldModel = @import("WorldModel.zig");
const ChunkModel = WorldModel.ChunkModel;

const Debug = @import("Debug.zig");

const WorldRenderer = @This();

const DrawList = List(DrawChunk);
const DrawChunk = struct {
    chunk: Chunk,
    chunk_model: ChunkModel,
    position: Vec3i,
};

allocator: Allocator,
world: *World,
world_model: *WorldModel,
world_model_manager: *WorldModel.Manager,
observer: Observer = undefined,
debug: Debug,

draw_list: DrawList = .{},
back_draw_list: DrawList = .{},
draw_list_mutex: Mutex = .{},

pub fn create(allocator: Allocator, world: *World) !*WorldRenderer {
    const self = try allocator.create(WorldRenderer);
    const world_model = try WorldModel.create(allocator, world);
    const world_model_manager = try WorldModel.Manager.create(allocator, world_model);
    self.* = WorldRenderer{
        .allocator = allocator,
        .world = world,
        .world_model = world_model,
        .world_model_manager = world_model_manager,
        .debug = try Debug.init(),
    };
    self.debug.setLight(vec3(.{ 1, 3, 2 }).norm() orelse unreachable);
    return self;
}

pub fn destroy(self: *WorldRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.stop();
    self.world_model.destroy();
    self.world_model_manager.destroy();
    self.draw_list.deinit(allocator);
    self.back_draw_list.deinit(allocator);
    self.debug.deinit();
}

pub fn start(self: *WorldRenderer, observer: Observer) !void {
    self.observer = observer;
    try self.world_model_manager.start(observer);
}

pub fn stop(self: *WorldRenderer) void {
    self.world_model_manager.stop();
}

pub fn setCameraMatrices(self: *WorldRenderer, view: nm.Mat4, proj: nm.Mat4) void {
    self.debug.setView(view);
    self.debug.setProj(proj);
}

pub fn onWorldUpdate(self: *WorldRenderer, world: *World) !void {
    try self.world_model_manager.onWorldUpdate(world);
}

pub fn update(self: *WorldRenderer) !void {
    const world_model = self.world_model;
    self.back_draw_list.clearRetainingCapacity();
    {
        world_model.chunk_models.map_mutex.lock();
        defer world_model.chunk_models.map_mutex.unlock();
        var iter = world_model.chunk_models.map.iterator();
        while (iter.next()) |kv| {
            const chunk = kv.key_ptr.*;
            const chunk_model = kv.value_ptr.*;
            const position = self.world.graph.positions.get(chunk);
            const draw_chunk = DrawChunk{
                .chunk = chunk,
                .chunk_model = chunk_model,
                .position = position,
            };
            try self.back_draw_list.append(self.allocator, draw_chunk);
        }
        std.mem.swap(DrawList, &self.draw_list, &self.back_draw_list);
    }
}

pub fn draw(self: *WorldRenderer) void {
    self.debug.start();
    self.debug.bindCube();
    for (self.draw_list.items) |draw_chunk| {
        const position = draw_chunk.position.cast(f32).addScalar(0.5).mulScalar(World.chunk_width);
        self.debug.drawCubeAssumeBound(position, 1, vec3(.{ 1, 1, 1 }));
    }
}
