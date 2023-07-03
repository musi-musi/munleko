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

const SelectionBox = @import("SelectionBox.zig");

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
selection_box: SelectionBox,

pub fn create(allocator: Allocator, session: *Session, scene: *Scene) !*SessionRenderer {
    const self = try allocator.create(SessionRenderer);
    errdefer allocator.destroy(self);
    const world_renderer = try WorldRenderer.create(allocator, scene, session.world);
    errdefer world_renderer.destroy();
    const selection_box = try SelectionBox.init();
    errdefer selection_box.deinit();
    selection_box.setColor(.{ 1, 1, 1 });
    selection_box.setPadding(0.01);
    self.* = SessionRenderer{
        .allocator = allocator,
        .scene = scene,
        .session = session,
        .world_renderer = world_renderer,
        .selection_box = selection_box,
    };
    return self;
}

pub fn destroy(self: *SessionRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.stop();
    self.world_renderer.destroy();
    self.scene.deinit();
    self.selection_box.deinit();
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

pub fn preTick(self: *SessionRenderer) !void {
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
    const tick_progress = self.session.tick_timer.progress();
    const eye_position = self.previous_player_eye_position.lerpTo(player.eyePosition(), tick_progress);
    self.scene.camera.setViewMatrix(nm.transform.createTranslate(eye_position.neg()).mul(player.lookMatrix()));

    gl.enable(.depth_test);
    gl.setDepthFunction(.less);
    gl.enable(.cull_face);

    gl.clearColor(self.scene.fog_color.addDimension(1).v);
    gl.clearDepth(.float, 1);
    gl.clear(.color_depth);
    self.world_renderer.draw();

    if (player.leko_cursor) |leko_cursor| {
        self.selection_box.setCamera(self.scene.camera);
        self.selection_box.draw(leko_cursor.cast(f32).v, .{ 1, 1, 1 });
    }
}
