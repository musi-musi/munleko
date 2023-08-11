const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec2 = nm.Vec2;
const vec2 = nm.vec2;

const Window = @import("window").Window;

const Engine = @import("../Engine.zig");
const Client = @import("../Client.zig");
const Player = Engine.Player;

const Input = @This();

pub const InputState = enum {
    gameplay,
    menu,
    radial,
};

client: *Client,

state: InputState = .gameplay,
previous_mouse_position: Vec2 = Vec2.zero,

pub fn init(client: *Client) Input {
    var self = Input{
        .client = client,
    };
    return self;
}

pub fn deinit(self: *Input) void {
    _ = self;
}

pub fn update(self: *Input) void {
    const w = self.client.window;
    if (w.buttonPressed(.f_10)) {
        w.setVsync(switch (w.vsync) {
            .enabled => .disabled,
            .disabled => .enabled,
        });
    }
    if (w.buttonPressed(.f_4)) {
        w.setDisplayMode(util.cycleEnum(w.display_mode));
    }
    if (self.client.session_state) |session_state| {
        const session = session_state.session;
        const p = &session.player;
        const mouse_position = vec2(w.mousePosition());
        defer self.previous_mouse_position = mouse_position;
        switch (self.state) {
            .gameplay, .radial => {
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
            },
            else => {
                p.input = .{};
            },
        }
        switch (self.state) {
            .gameplay => {
                if (w.buttonPressed(.g)) {
                    p.settings.move_mode = util.cycleEnum(p.settings.move_mode);
                }
                if (w.buttonPressed(.x)) {
                    p.leko_edit_mode = util.cycleEnum(p.leko_edit_mode);
                }
                if (p.leko_edit_mode == .place and w.buttonPressed(.mouse_2)) {
                    p.leko_place_mode = util.cycleEnum(p.leko_place_mode);
                }
                if (w.buttonPressed(.mouse_1)) {
                    p.input.trigger_primary = true;
                }
                p.input.primary = w.buttonHeld(.mouse_1);
                const mouse_delta = mouse_position.sub(self.previous_mouse_position).mulScalar(0.1);
                p.updateLookFromMouse(mouse_delta);
                if (w.buttonHeld(.c)) {
                    self.setState(.radial);
                }
            },
            .radial => {
                const selection = self.client.gui.showEquipSelectRadial(mouse_position, Engine.Player.leko_equip_radial_len, &p.leko_equip_radial);
                if (!w.buttonHeld(.c)) {
                    if (selection != null) {
                        p.leko_equip = selection;
                        p.leko_edit_mode = .place;
                    }
                    self.setState(.gameplay);
                }
            },
            else => {},
        }
        if (w.buttonPressed(.grave)) {
            switch (self.state) {
                .gameplay => self.setState(.menu),
                .menu => self.setState(.gameplay),
                else => {},
            }
        }
    }
}

pub fn setState(self: *Input, state: InputState) void {
    const w = self.client.window;
    switch (state) {
        .gameplay => {
            self.previous_mouse_position = vec2(w.mousePosition());
            w.setMouseMode(.disabled);
        },
        .menu => {
            w.setMouseMode(.visible);
            const center = nm.vec2u(w.size).cast(f32).divScalar(2);
            w.setMousePosition(center.v);
        },
        .radial => {
            w.setMouseMode(.visible);
            const center = nm.vec2u(w.size).cast(f32).divScalar(2);
            w.setMousePosition(center.v);
        },
    }
    self.state = state;
}
