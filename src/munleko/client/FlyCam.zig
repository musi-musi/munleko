const std = @import("std");
const nm = @import("nm");
const w = @import("window");

const Vec2 = nm.Vec2;
const Vec3 = nm.Vec3;
const vec2 = nm.vec2;
const vec3 = nm.vec3;

const Window = w.Window;
const Timer = std.time.Timer;

const Self = @This();

sensitivity: f32 = 0.1,
invert_y: bool = false,
look_angles: Vec2 = Vec2.zero,
prev_cursor: Vec2 = Vec2.zero,
position: Vec3 = Vec3.zero,
move_speed: f32 = 5,
timer: Timer = undefined,
mutex: std.Thread.Mutex = .{},

pub fn init(window: Window) Self {
    var self = Self{};
    self.prev_cursor = vec2(window.mousePosition());
    self.timer = Timer.start() catch unreachable;
    return self;
}

pub fn update(self: *Self, window: Window) void {
    const mouse_pos = vec2(window.mousePosition());
    if (window.mouse_mode == .disabled) {
        const dt_ns = self.timer.read();
        const dmouse = mouse_pos.sub(self.prev_cursor).mulScalar(self.sensitivity);
        var look_x = self.look_angles.v[0] + dmouse.v[0];
        var look_y = self.look_angles.v[1] + if (self.invert_y) -dmouse.v[1] else dmouse.v[1];
        if (look_y > 90) look_y = 90;
        if (look_y < -90) look_y = -90;
        look_x = @mod(look_x, 360);
        self.look_angles.v = .{ look_x, look_y };
        const dt = @as(f32, @floatCast(@as(f64, @floatFromInt(dt_ns)) / std.time.ns_per_s));
        var move = Vec3.zero;
        if (window.buttonHeld(.d)) move.v[0] += 1;
        if (window.buttonHeld(.a)) move.v[0] -= 1;
        if (window.buttonHeld(.space)) move.v[1] += 1;
        if (window.buttonHeld(.left_shift)) move.v[1] -= 1;
        if (window.buttonHeld(.w)) move.v[2] += 1;
        if (window.buttonHeld(.s)) move.v[2] -= 1;
        move = (move.norm() orelse Vec3.zero).mulScalar(self.move_speed * dt);
        move = self.lookMatrix().transpose().transformDirection(move);
        self.position = self.position.add(move);
    }
    self.prev_cursor = mouse_pos;
    self.timer.reset();
}

pub fn positionMatrix(self: Self) nm.Mat4 {
    return nm.transform.createTranslate(self.position.neg());
}

pub fn lookMatrix(self: Self) nm.Mat4 {
    return nm.transform.createEulerZXY(nm.vec3(.{
        -self.look_angles.get(.y) * std.math.pi / 180.0,
        -self.look_angles.get(.x) * std.math.pi / 180.0,
        0,
    }));
}

pub fn viewMatrix(self: Self) nm.Mat4 {
    return self.positionMatrix().mul(self.lookMatrix());
}
