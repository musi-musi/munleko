const std = @import("std");

pub const Session = @import("Session.zig");

const Allocator = std.mem.Allocator;

pub const Engine = struct {
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self {
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn createSession(self: *Self, callbacks: Session.Callbacks) !Session {
        return Session.init(self.allocator, callbacks);
    }

};