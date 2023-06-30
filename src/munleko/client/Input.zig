const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec2 = nm.Vec2;
const vec2 = nm.vec2;

const Window = @import("window").Window;

const Engine = @import("../Engine.zig");
const Player = Engine.Player;

const Input = @This();

pub const InputState = enum {
    gameplay,
    menu,
};

window: *Window,
state: InputState = .gameplay,
player: *Player,
previous_mouse_position: Vec2 = Vec2.zero,

pub fn init(window: *Window, player: *Player) Input {
    var self = Input{
        .window = window,
        .player = player,
        .previous_mouse_position = vec2(window.mousePosition()),
    };
    return self;
}

pub fn deinit(self: *Input) void {
    _ = self;
}

pub fn frame(self: *Input) void {
    const w = self.window;
    const p = self.player;
    const mouse_position = vec2(w.mousePosition());
    defer self.previous_mouse_position = mouse_position;
    switch (self.state) {
        .gameplay => {
            if (w.buttonPressed(.z)) {
                p.settings.move_mode = util.cycleEnum(p.settings.move_mode);
            }
            if (w.buttonPressed(.f)) {
                p.leko_edit_mode = util.cycleEnum(p.leko_edit_mode);
            }
            var player_move = nm.Vec3.zero;
            if (w.buttonHeld(.d)) player_move.v[0] += 1;
            if (w.buttonHeld(.a)) player_move.v[0] -= 1;
            if (w.buttonHeld(.space)) player_move.v[1] += 1;
            if (w.buttonHeld(.left_shift)) player_move.v[1] -= 1;
            if (w.buttonHeld(.w)) player_move.v[2] += 1;
            if (w.buttonHeld(.s)) player_move.v[2] -= 1;
            p.input.move = player_move;
            if (w.buttonHeld(.space)) {
                p.input.trigger_jump = true;
            }
            if (w.buttonPressed(.mouse_1)) {
                p.input.trigger_primary = true;
            }
            const mouse_delta = mouse_position.sub(self.previous_mouse_position).mulScalar(0.1);
            p.updateLookFromMouse(mouse_delta);
        },
        .menu => {
            self.player.input = .{};
        },
    }
}

pub fn setState(self: *Input, state: InputState) void {
    switch (state) {
        .gameplay => {
            self.window.setMouseMode(.disabled);
        },
        .menu => {
            self.window.setMouseMode(.visible);
        },
    }
    self.state = state;
}
