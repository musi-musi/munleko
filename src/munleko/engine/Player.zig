const std = @import("std");
const nm = @import("nm");

const Session = @import("Session.zig");
const World = @import("World.zig");

const Observer = World.Observer;

const Vec2 = nm.Vec2;
const Vec3 = nm.Vec3;
const vec2 = nm.vec2;
const vec3 = nm.vec3;

const Player = @This();

world: *World,

position: Vec3,
look_angles: Vec2 = Vec2.zero,
observer: Observer,

input: Input = .{},
settings: Settings = .{},

pub const Input = struct {
    move: Vec3 = Vec3.zero,
};

pub const Settings = struct {
    move_speed: f32 = 5,
    noclip_move_speed: f32 = 32,
    move_mode: MoveMode = .normal,
};

pub const MoveMode = enum {
    normal,
    noclip,
};

pub fn init(world: *World, position: Vec3) !Player {
    const observer = try world.observers.create(position.cast(i32));
    return Player{
        .world = world,
        .position = position,
        .observer = observer,
    };
}

pub fn deinit(self: Player) void {
    self.world.observers.delete(self.observer);
}

pub fn onTick(self: *Player, session: *Session) void {
    self.moveNoclip(session);
    self.world.observers.setPosition(self.observer, self.position.cast(i32));
}

fn moveNoclip(self: *Player, session: *Session) void {
    const dt = 1 / session.tick_rate;
    const face_angle = std.math.degreesToRadians(f32, self.look_angles.v[0]);
    const sin = @sin(-face_angle);
    const cos = @cos(-face_angle);
    const face_forward = vec2(.{ -sin, cos });
    const face_right = vec2(.{ cos, sin });
    const move_horizon = vec2(.{ self.input.move.v[0], self.input.move.v[2] }).norm() orelse Vec2.zero;
    const move_horizon_rotated = face_forward.mulScalar(move_horizon.v[1]).add(face_right.mulScalar(move_horizon.v[0]));
    self.position.v[0] += move_horizon_rotated.v[0] * dt * self.settings.noclip_move_speed;
    self.position.v[1] += self.input.move.v[1] * dt * self.settings.noclip_move_speed;
    self.position.v[2] += move_horizon_rotated.v[1] * dt * self.settings.noclip_move_speed;
}

pub fn updateLookFromMouse(self: *Player, mouse_delta: Vec2) void {
    const look_x = self.look_angles.v[0] + mouse_delta.v[0];
    const look_y = self.look_angles.v[1] + mouse_delta.v[1];
    self.look_angles.v[0] = @mod(look_x, 360);
    self.look_angles.v[1] = std.math.clamp(look_y, -90, 90);
}

pub fn lookMatrix(self: Player) nm.Mat4 {
    return nm.transform.createEulerZXY(nm.vec3(.{
        -self.look_angles.get(.y) * std.math.pi / 180.0,
        -self.look_angles.get(.x) * std.math.pi / 180.0,
        0,
    }));
}
