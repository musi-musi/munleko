const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Scene = @import("Scene.zig");
const WorldRenderer = @import("WorldRenderer.zig");
const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;
const World = Engine.World;
const Observer = World.Observer;

const Allocator = std.mem.Allocator;

const SessionRenderer = @This();

allocator: Allocator,
scene: Scene,
session: *Session,
world_renderer: *WorldRenderer,

pub fn create(allocator: Allocator, session: *Session) !*SessionRenderer {
    const self = try allocator.create(SessionRenderer);
    self.* = SessionRenderer{
        .allocator = allocator,
        .scene = undefined,
        .session = session,
        .world_renderer = undefined,
    };
    try self.scene.init();
    self.world_renderer = try WorldRenderer.create(allocator, &self.scene, session.world);
    return self;
}

pub fn destroy(self: *SessionRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.stop();
    self.world_renderer.destroy();
    self.scene.deinit();
}

pub fn start(self: *SessionRenderer, observer: Observer) !void {
    try self.world_renderer.start(observer);
}

pub fn stop(self: *SessionRenderer) void {
    self.world_renderer.stop();
}

pub fn onWorldUpdate(self: *SessionRenderer, world: *World) !void {
    try self.world_renderer.onWorldUpdate(world);
}

pub fn update(self: *SessionRenderer) !void {
    try self.world_renderer.update();
}

pub fn draw(self: *SessionRenderer) void {
    self.world_renderer.draw(&self.scene);
}

pub fn setDirectionalLight(self: *SessionRenderer, light: Vec3) void {
    self.scene.setDirectionalLight(light);
    self.world_renderer.setDirectionalLight(light);
}

pub fn setCameraMatrices(self: *SessionRenderer, view: nm.Mat4, proj: nm.Mat4) void {
    self.scene.setCameraMatrices(view, proj);
    self.world_renderer.setCameraMatrices(view, proj);
}
