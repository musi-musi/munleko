const std = @import("std");
const nm = @import("nm");
const util = @import("util");

const Engine = @import("../Engine.zig");
const World = @import("World.zig");

const Allocator = std.mem.Allocator;

const Save = @This();

allocator: Allocator,
root_path: []const u8,

pub fn create(allocator: Allocator, root_path: []const u8) !*Save {
    const owned_root_path = try allocator.dupe(u8, root_path);
    errdefer allocator.free(owned_root_path);
    const self = try allocator.create(Save);
    self.* = .{
        .allocator = allocator,
        .root_path = owned_root_path,
    };
    return self;
}

pub fn destroy(self: *Save) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    allocator.free(self.root_path);
}
