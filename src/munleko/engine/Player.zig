const std = @import("std");
const nm = @import("nm");

const Session = @import("Session.zig");
const World = @import("World.zig");

const leko = @import("leko.zig");

const Observer = World.Observer;

const Vec2 = nm.Vec2;
const Vec3 = nm.Vec3;
const vec2 = nm.vec2;
const vec3 = nm.vec3;

const Bounds3 = nm.Bounds3;

const Player = @This();

world: *World,

position: Vec3,
hull: Bounds3 = .{
    .center = undefined,
    .radius = vec3(.{ 1.5 / 2.0, 3.5 / 2.0, 1.5 / 2.0 }),
},
eye_height: f32 = 1.5,
look_angles: Vec2 = Vec2.zero,
observer: Observer,

input: Input = .{},
settings: Settings = .{},

pub const Input = struct {
    move: Vec3 = Vec3.zero,
};

pub const Settings = struct {
    move_speed: f32 = 10,
    noclip_move_speed: f32 = 32,
    move_mode: MoveMode = .normal,
};

pub const MoveMode = enum {
    normal,
    noclip,
};

pub fn init(world: *World, position: Vec3) !Player {
    const observer = try world.observers.create(position.cast(i32));
    var self = Player{
        .world = world,
        .position = position,
        .observer = observer,
    };
    self.hull.center = position;
    return self;
}

pub fn deinit(self: Player) void {
    self.world.observers.delete(self.observer);
}

pub fn onTick(self: *Player, session: *Session) void {
    switch (self.settings.move_mode) {
        .normal => self.moveNormal(session),
        .noclip => self.moveNoclip(session),
    }
    self.world.observers.setPosition(self.observer, self.position.cast(i32));
}

fn moveNoclip(self: *Player, session: *Session) void {
    const dt = 1 / session.tick_rate;
    const move_xz = self.getMoveXZ();
    self.hull.center.v[0] += move_xz.v[0] * dt * self.settings.noclip_move_speed;
    self.hull.center.v[1] += self.input.move.v[1] * dt * self.settings.noclip_move_speed;
    self.hull.center.v[2] += move_xz.v[1] * dt * self.settings.noclip_move_speed;
    self.position = self.hull.center;
}

fn moveNormal(self: *Player, session: *Session) void {
    const world = session.world;
    const dt = 1 / session.tick_rate;
    const move_xz = self.getMoveXZ().mulScalar(dt * self.settings.move_speed);
    const move_y = self.input.move.v[1] * dt * self.settings.move_speed;
    _ = leko.physics.moveBoundsAxis(world, &self.hull, move_xz.v[0], .x, leko.physics.lekoTypeIsSolid);
    _ = leko.physics.moveBoundsAxis(world, &self.hull, move_y, .y, leko.physics.lekoTypeIsSolid);
    _ = leko.physics.moveBoundsAxis(world, &self.hull, move_xz.v[1], .z, leko.physics.lekoTypeIsSolid);
    self.position = self.hull.center;
    // self.position.v[0] += move_xz.v[0] * dt * self.settings.move_speed;
    // self.position.v[1] += self.input.move.v[1] * dt * self.settings.move_speed;
    // self.position.v[2] += move_xz.v[1] * dt * self.settings.move_speed;
}

fn getMoveXZ(self: Player) Vec2 {
    const face_angle = std.math.degreesToRadians(f32, self.look_angles.v[0]);
    const sin = @sin(-face_angle);
    const cos = @cos(-face_angle);
    const face_forward = vec2(.{ -sin, cos });
    const face_right = vec2(.{ cos, sin });
    const move = vec2(.{ self.input.move.v[0], self.input.move.v[2] }).norm() orelse Vec2.zero;
    const move_rotated = face_forward.mulScalar(move.v[1]).add(face_right.mulScalar(move.v[0]));
    return move_rotated;
}

pub fn updateLookFromMouse(self: *Player, mouse_delta: Vec2) void {
    const look_x = self.look_angles.v[0] + mouse_delta.v[0];
    const look_y = self.look_angles.v[1] + mouse_delta.v[1];
    self.look_angles.v[0] = @mod(look_x, 360);
    self.look_angles.v[1] = std.math.clamp(look_y, -90, 90);
}

pub fn eyePosition(self: Player) Vec3 {
    var position = self.position;
    position.ptrMut(.y).* += self.eye_height;
    return position;
}

pub fn lookMatrix(self: Player) nm.Mat4 {
    return nm.transform.createEulerZXY(nm.vec3(.{
        -self.look_angles.get(.y) * std.math.pi / 180.0,
        -self.look_angles.get(.x) * std.math.pi / 180.0,
        0,
    }));
}
