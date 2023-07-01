const std = @import("std");
const util = @import("util");
const nm = @import("nm");
const gl = @import("gl");

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Scene = @import("Scene.zig");
const WorldRenderer = @import("WorldRenderer.zig");
const Client = @import("../../Client.zig");
const Engine = @import("../../Engine.zig");

const Camera = Scene.Camera;

const Session = Engine.Session;
const World = Engine.World;
const Assets = Engine.Assets;
const Observer = World.Observer;

const Allocator = std.mem.Allocator;

const SessionRenderer = @This();

allocator: Allocator,
scene: *Scene,
session: *Session,
world_renderer: *WorldRenderer,
previous_player_eye_position: Vec3 = Vec3.zero,

pub fn create(allocator: Allocator, session: *Session, scene: *Scene) !*SessionRenderer {
    const self = try allocator.create(SessionRenderer);
    errdefer allocator.destroy(self);
    const world_renderer = try WorldRenderer.create(allocator, scene, session.world);
    errdefer world_renderer.destroy();
    self.* = SessionRenderer{
        .allocator = allocator,
        .scene = scene,
        .session = session,
        .world_renderer = world_renderer,
    };
    return self;
}

pub fn destroy(self: *SessionRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.stop();
    self.world_renderer.destroy();
    self.scene.deinit();
}

pub fn applyAssets(self: *SessionRenderer, assets: *const Assets) !void {
    try self.world_renderer.applyAssets(assets);
}

pub fn start(self: *SessionRenderer, observer: Observer) !void {
    self.previous_player_eye_position = self.session.player.eyePosition();
    try self.world_renderer.start(observer);
}

pub fn stop(self: *SessionRenderer) void {
    self.world_renderer.stop();
}

pub fn onTick(self: *SessionRenderer) !void {
    self.previous_player_eye_position = self.session.player.eyePosition();
}

pub fn onWorldUpdate(self: *SessionRenderer, world: *World) !void {
    try self.world_renderer.onWorldUpdate(world);
}

pub fn update(self: *SessionRenderer) !void {
    try self.world_renderer.update();
}

pub fn draw(self: *SessionRenderer) void {
    const player = &self.session.player;
    const eye_position = self.previous_player_eye_position.lerpTo(player.eyePosition(), self.session.tickProgress());
    self.scene.camera.setViewMatrix(nm.transform.createTranslate(eye_position.neg()).mul(player.lookMatrix()));

    gl.enable(.depth_test);
    gl.setDepthFunction(.less);
    gl.enable(.cull_face);

    gl.clearColor(self.scene.fog_color.addDimension(1).v);
    gl.clearDepth(.float, 1);
    gl.clear(.color_depth);
    self.world_renderer.draw();
}
