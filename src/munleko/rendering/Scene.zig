const std = @import("std");
const nm = @import("nm");

const Vec3 = nm.Vec3;
const Mat4 = nm.Mat4;

const Debug = @import("Debug.zig");

const Scene = @This();

debug: Debug,

directional_light: Vec3 = Vec3.zero,
camera_view: Mat4 = Mat4.identity,
camera_projection: Mat4 = Mat4.identity,

fog_color: Vec3 = Vec3.zero,
fog_start: f32 = 16,
fog_end: f32 = 100,
fog_power: f32 = 1.5,

pub fn init(self: *Scene) !void {
    self.* = .{
        .debug = try Debug.init(),
    };
}

pub fn deinit(self: *Scene) void {
    self.debug.deinit();
}

pub fn setupDebug(self: *Scene) *Debug {
    self.debug.setView(self.camera_view);
    self.debug.setProj(self.camera_projection);
    self.debug.setLight(self.directional_light);
    return &self.debug;
}