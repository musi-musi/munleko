const std = @import("std");
const util = @import("util");
const nm = @import("nm");
const gl = @import("gl");

const Renderer = @This();

pub const Debug = @import("renderer/Debug.zig");
pub const SessionRenderer = @import("renderer/SessionRenderer.zig");
pub const WorldRenderer = @import("renderer/WorldRenderer.zig");
pub const Scene = @import("renderer/Scene.zig");
pub const PlayerRenderer = @import("renderer/PlayerRenderer.zig");

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;

const Allocator = std.mem.Allocator;

allocator: Allocator,
scene: Scene,

pub fn create(allocator: Allocator) !*Renderer {
    const self = try allocator.create(Renderer);
    errdefer allocator.destroy(self);
    self.* = .{
        .allocator = allocator,
        .scene = undefined,
    };
    return self;
}

pub fn destroy(self: *Renderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.scene.deinit();
}

pub fn start(self: *Renderer) !void {
    try self.scene.init();
}

pub fn stop(self: *Renderer) void {
    _ = self;
}

pub fn createSessionRenderer(self: *Renderer, session: *Session) !*SessionRenderer {
    return try SessionRenderer.create(self.allocator, session, &self.scene);
}
