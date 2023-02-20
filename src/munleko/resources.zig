const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ResourceManager = struct {
    allocator: Allocator,

    pub fn create(allocator: Allocator) !*ResourceManager {
        const self = try allocator.create(ResourceManager);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    pub fn destroy(self: *ResourceManager) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
    }
};