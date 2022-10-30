const std = @import("std");
const nm = @import("nm");
const w = @import("window");

const Vec2 = nm.Vec2;
const vec2 = nm.vec2;

const Window = w.Window;

const Self = @This();

window: *Window,
sensitivity: f32 = 0.1,
invert_y: bool = false,
look_angles: Vec2 = Vec2.zero,
prev_cursor: Vec2 = Vec2.zero,

pub fn init(window: *Window) Self {
    var self = Self {
        .window = window,
    };
    self.prev_cursor = vec2(window.mousePosition());
    return self;
}

pub fn update(self: *Self) void {
    const mouse_pos = vec2(self.window.mousePosition());
    if (self.window.mouse_mode == .disabled) {
        const delta = mouse_pos.sub(self.prev_cursor).mulScalar(self.sensitivity);
        var look_x = self.look_angles.v[0] + delta.v[0];
        var look_y = self.look_angles.v[1] + if (self.invert_y) -delta.v[1] else delta.v[1];
        if (look_y > 90) look_y = 90;
        if (look_y < -90) look_y = -90;
        look_x = @mod(look_x, 360);
        self.look_angles.v = .{
            look_x, look_y
        };
    }
    self.prev_cursor = mouse_pos;
}

pub fn viewMatrix(self: Self) nm.Mat4 {
    return nm.transform.createEulerZXY(nm.vec3(.{
        -self.look_angles.get(.y) * std.math.pi / 180.0,
        -self.look_angles.get(.x) * std.math.pi / 180.0,
        0,
    }));
}
