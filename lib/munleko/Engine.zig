const std = @import("std");

const Allocator = std.mem.Allocator;

const Session = @import("Session.zig");

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
