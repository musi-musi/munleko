const std = @import("std");
const util = @import("util");

const LekoRenderer = @This();

const Allocator = std.mem.Allocator;

allocator: Allocator,

pub fn create(allocator: Allocator) !*LekoRenderer {
    const self = try allocator.create(LekoRenderer);
    self.* = .{
        .allocator = allocator,
    };
    return self;
}

pub fn destroy(self: *LekoRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
}
