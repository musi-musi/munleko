const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const Thread = std.Thread;
const Atomic = std.atomic.Atomic;
const AtomicFlag = util.AtomicFlag;
const Mutex = Thread.Mutex;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;
const World = Engine.World;
const AssetDatabase = Engine.AssetDatabase;
const Chunk = World.Chunk;
const Observer = World.Observer;

const Scene = @import("Scene.zig");
const WorldModel = @import("WorldModel.zig");
const ChunkModel = WorldModel.ChunkModel;
const leko_mesh = @import("leko_mesh.zig");
const LekoMeshRenderer = @import("LekoMeshRenderer.zig");

const Debug = @import("Debug.zig");

const WorldRenderer = @This();

const DrawList = List(DrawChunk);
pub const DrawChunk = struct {
    chunk: Chunk,
    chunk_model: ChunkModel,
    // load_state: World.ChunkLoadState,
    position: Vec3i,
    bounds_center: Vec3,
};

allocator: Allocator,
scene: *Scene,
world: *World,
world_model: *WorldModel,
world_model_manager: *WorldModel.Manager,
observer: Observer = undefined,

draw_list_update_thread: Thread = undefined,
is_running: AtomicFlag = .{},

draw_list: DrawList = .{},
back_draw_list: DrawList = .{},
draw_list_mutex: Mutex = .{},

chunk_map: ChunkMap = .{},
chunk_map_mutex: Mutex = .{},

leko_mesh_renderer: *LekoMeshRenderer,

const ChunkMap = std.HashMapUnmanaged(Chunk, World.ChunkLoadState, Chunk.HashContext, std.hash_map.default_max_load_percentage);

pub fn create(allocator: Allocator, scene: *Scene, world: *World) !*WorldRenderer {
    const self = try allocator.create(WorldRenderer);
    const world_model = try WorldModel.create(allocator, world);
    const world_model_manager = try WorldModel.Manager.create(allocator, world_model);
    self.* = WorldRenderer{
        .allocator = allocator,
        .scene = scene,
        .world = world,
        .world_model = world_model,
        .world_model_manager = world_model_manager,
        .leko_mesh_renderer = try LekoMeshRenderer.create(allocator, scene, world_model),
    };
    return self;
}

pub fn destroy(self: *WorldRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.stop();

    self.world_model.destroy();
    self.world_model_manager.destroy();
    self.leko_mesh_renderer.destroy();

    self.draw_list.deinit(allocator);
    self.back_draw_list.deinit(allocator);
    self.chunk_map.deinit(allocator);
}

pub fn applyAssets(self: *WorldRenderer, assets: *const AssetDatabase) !void {
    try self.world_model.applyAssets(assets);
}

pub fn start(self: *WorldRenderer, observer: Observer) !void {
    if (self.is_running.get()) {
        @panic("world renderer is already running");
    }
    self.observer = observer;
    self.is_running.set(true);
    self.draw_list_update_thread = try Thread.spawn(.{}, drawListUpdateThreadMain, .{self});
    try self.world_model_manager.start(observer);
}

pub fn stop(self: *WorldRenderer) void {
    if (self.is_running.get()) {
        self.is_running.set(false);
        self.world_model.dirty_event.set();
        self.draw_list_update_thread.join();
        self.world_model_manager.stop();
    }
}

fn drawListUpdateThreadMain(self: *WorldRenderer) !void {
    while (self.is_running.get()) {
        self.world_model.dirty_event.wait();
        self.world_model.dirty_event.reset();
        try self.updateDrawList();
        self.swapDrawLists();
    }
}

fn updateDrawList(self: *WorldRenderer) !void {
    const world_model = self.world_model;
    self.back_draw_list.clearRetainingCapacity();
    self.world_model.chunk_models.map_mutex.lock();
    defer self.world_model.chunk_models.map_mutex.unlock();
    var iter = world_model.chunk_models.map.iterator();
    while (iter.next()) |kv| {
        const chunk_model = kv.value_ptr.*;
        const status = self.world_model.chunk_models.statuses.getPtr(chunk_model);
        status.mutex.lock();
        defer status.mutex.unlock();
        if (status.state != .ready) {
            continue;
        }
        const chunk = status.chunk;
        const position = self.world.graph.positions.get(status.chunk);
        const bounds_center = position.cast(f32).addScalar(0.5).mulScalar(World.chunk_width);
        const draw_chunk = DrawChunk{
            .chunk = chunk,
            .chunk_model = chunk_model,
            .position = position,
            .bounds_center = bounds_center,
        };
        try self.back_draw_list.append(self.allocator, draw_chunk);
    }
}

fn swapDrawLists(self: *WorldRenderer) void {
    self.draw_list_mutex.lock();
    defer self.draw_list_mutex.unlock();
    std.mem.swap(DrawList, &self.draw_list, &self.back_draw_list);
}

pub fn onWorldUpdate(self: *WorldRenderer, world: *World) !void {
    try self.world_model_manager.onWorldUpdate(world);
}

pub fn update(self: *WorldRenderer) !void {
    _ = self;
}

pub fn draw(self: *WorldRenderer) void {
    // const debug = self.scene.setupDebug();
    // debug.start();
    // debug.bindCube();
    self.draw_list_mutex.lock();
    defer self.draw_list_mutex.unlock();
    // for (self.draw_list.items) |draw_chunk| {
    //     const position = draw_chunk.position.cast(f32).addScalar(0.5).mulScalar(World.chunk_width);
    //     debug.drawCubeAssumeBound(position, 1, vec3(.{ 1, 1, 1 }));
    // }
    self.leko_mesh_renderer.updateAndDrawLekoMeshes(self.draw_list.items);
}
