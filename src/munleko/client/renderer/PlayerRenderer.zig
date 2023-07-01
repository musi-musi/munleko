const std = @import("std");
const nm = @import("nm");
const util = @import("util");

const Allocator = std.mem.Allocator;

const Engine = @import("../../Engine.zig");
const Client = @import("../../Client.zig");

const Scene = @import("Scene.zig");
const SelectionBox = @import("SelectionBox.zig");

const Player = Engine.Player;

const PlayerRenderer = @This();

allocator: Allocator,
scene: *Scene,
player: *Player,

selection_box: SelectionBox,

pub fn create(allocator: Allocator, scene: *Scene, player: *Player) !*PlayerRenderer {
    const self = try allocator.create(PlayerRenderer);
    errdefer allocator.destroy(self);
    const selection_box = try SelectionBox.init();
    errdefer selection_box.deinit();
    selection_box.setColor(.{ 1, 1, 1 });
    selection_box.setPadding(0.01);
    self.* = .{
        .allocator = allocator,
        .scene = scene,
        .player = player,
        .selection_box = selection_box,
    };
    return self;
}

pub fn destroy(self: *PlayerRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.selection_box.deinit();
}

pub fn draw(self: *PlayerRenderer) void {
    if (self.player.leko_cursor) |leko_cursor| {
        self.selection_box.setCamera(self.scene.camera);
        self.selection_box.draw(leko_cursor.cast(f32).v, .{ 1, 1, 1 });
    }
}
