const std = @import("std");
const nm = @import("nm");

const Debug = @import("Debug.zig");

const Scene = @This();

debug: Debug,

pub fn init(self: *Scene) !void {
    self.* = .{
        .debug = try Debug.init(),
    };
}

pub fn deinit(self: *Scene) void {
    self.debug.deinit();
}

pub fn setCameraMatrices(self: *Scene, view: nm.Mat4, proj: nm.Mat4) void {
    self.debug.setView(view);
    self.debug.setProj(proj);
}

pub fn setDirectionalLight(self: *Scene, light: nm.Vec3) void {
    self.debug.setLight(light);
}