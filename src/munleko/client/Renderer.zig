const std = @import("std");
const util = @import("util");
const nm = @import("nm");
const gl = @import("gl");

const Renderer = @This();

pub const Debug = @import("renderer/Debug.zig");
pub const SessionRenderer = @import("renderer/SessionRenderer.zig");
pub const WorldRenderer = @import("renderer/WorldRenderer.zig");
pub const Scene = @import("renderer/Scene.zig");
pub const Resources = @import("renderer/Resources.zig");

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;

const Allocator = std.mem.Allocator;

allocator: Allocator,
engine: *Engine,
resources: *Resources,

pub fn create(allocator: Allocator, engine: *Engine) !*Renderer {
    const self = try allocator.create(Renderer);
    errdefer allocator.destroy(self);
    const resources = try Resources.create(allocator);
    errdefer resources.destroy();
    self.* = .{
        .allocator = allocator,
        .engine = engine,
        .resources = resources,
    };
    return self;
}

pub fn destroy(self: *Renderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.resources.destroy();
}

pub fn createSessionRenderer(self: *Renderer, session: *Session) !*SessionRenderer {
    const session_renderer = try SessionRenderer.create(self.allocator, session);
    try session_renderer.applyResources(self.resources);
    return session_renderer;
}

pub fn applyAssets(self: *Renderer, assets: *Engine.Assets) !void {
    try self.resources.applyAssets(assets);
}
