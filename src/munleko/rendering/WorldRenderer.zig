const std = @import("std");

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;
const World = Engine.World;
const Observer = World.Observer;

const WorldModel = @import("WorldModel.zig");

const Allocator = std.mem.Allocator;

const WorldRenderer = @This();

allocator: Allocator,
world: *World,
world_model: *WorldModel,
world_model_manager: *WorldModel.Manager,
observer: Observer = undefined,

pub fn create(allocator: Allocator, world: *World) !*WorldRenderer {
    const self = try allocator.create(WorldRenderer);
    const world_model = try WorldModel.create(allocator, world);
    const world_model_manager = try WorldModel.Manager.create(allocator, world_model);
    self.* = WorldRenderer{
        .allocator = allocator,
        .world = world,
        .world_model = world_model,
        .world_model_manager = world_model_manager,
    };
    return self;
}

pub fn destroy(self: *WorldRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.stop();
    self.world_model.destroy();
    self.world_model_manager.destroy();
}

pub fn start(self: *WorldRenderer, observer: Observer) !void {
    self.observer = observer;
    try self.world_model_manager.start(observer);
}

pub fn stop(self: *WorldRenderer) void {
    self.world_model_manager.stop();
}

pub fn onWorldUpdate(self: *WorldRenderer, world: *World) !void {
    try self.world_model_manager.onWorldUpdate(world);
}
