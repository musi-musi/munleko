const std = @import("std");

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;
const World = Engine.World;

const Allocator = std.mem.Allocator;

const SessionRenderer = @This();

allocator: Allocator,
session: *Session,

pub fn create(allocator: Allocator, session: *Session) !*SessionRenderer {
    const self = try allocator.create(SessionRenderer);
    self.* = SessionRenderer{
        .allocator = allocator,
        .session = session,
    };
    return self;
}

pub fn destroy(self: *SessionRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
}