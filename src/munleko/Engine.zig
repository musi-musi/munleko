const std = @import("std");

pub const Session = @import("engine/Session.zig");
pub const World = @import("engine/World.zig");
pub const leko = @import("engine/leko.zig");

const Allocator = std.mem.Allocator;

allocator: Allocator,

const Engine = @This();

pub fn init(allocator: Allocator) !Engine {
    return Engine {
        .allocator = allocator,
    };
}

pub fn deinit(self: *Engine) void {
    _ = self;
}

pub fn createSession(self: *Engine) !*Session {
    return Session.create(self.allocator);
}
