const std = @import("std");
const util = @import("util");
const nm = @import("nm");
const gl = @import("gl");

const Renderer = @This();

pub const Debug = @import("renderer/Debug.zig");
pub const SessionRenderer = @import("renderer/SessionRenderer.zig");
pub const WorldRenderer = @import("renderer/WorldRenderer.zig");
pub const Scene = @import("renderer/Scene.zig");

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;

const Allocator = std.mem.Allocator;

allocator: Allocator,
engine: *Engine,

pub fn create(allocator: Allocator, engine: *Engine) !*Renderer {
    const self = try allocator.create(Renderer);
    errdefer allocator.destroy(self);
    self.* = .{
        .allocator = allocator,
        .engine = engine,
    };
    return self;
}

pub fn destroy(self: *Renderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
}

pub fn createSessionRenderer(self: *Renderer, session: *Session) !*SessionRenderer {
    const session_renderer = try SessionRenderer.create(self.allocator, session);
    try session_renderer.applyAssets(self.engine.assets);
    return session_renderer;
}
