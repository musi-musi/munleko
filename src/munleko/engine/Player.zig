const std = @import("std");
const nm = @import("nm");

const Session = @import("Session.zig");
const World = @import("World.zig");

const leko = @import("leko.zig");
const Physics = @import("Physics.zig");
const Observer = World.Observer;

const Vec2 = nm.Vec2;
const vec2 = nm.vec2;
const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Bounds3 = nm.Bounds3;

const Player = @This();

world: *World,

position: Vec3,
hull: Bounds3 = .{
    .center = undefined,
    .radius = vec3(.{ 1.5 / 2.0, 3.5 / 2.0, 1.5 / 2.0 }),
},
is_grounded: bool = false,
velocity_y: f32 = 0,

eye_height: f32 = 1.5,
eye_height_offset: f32 = 0,

leko_cursor: ?Vec3i = null,

look_angles: Vec2 = Vec2.zero,
observer: Observer,
input: Input = .{},
settings: Settings = .{},

pub const Input = struct {
    move: Vec3 = Vec3.zero,
    trigger_jump: bool = false,
};

pub const Settings = struct {
    move_speed: f32 = 15,
    jump_height: f32 = 2.25,
    noclip_move_speed: f32 = 32,
    move_mode: MoveMode = .normal,
    interact_range: f32 = 10,
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
    defer self.input.trigger_jump = false;
    switch (self.settings.move_mode) {
        .normal => self.moveNormal(session),
        .noclip => self.moveNoclip(session),
    }
    self.position = self.hull.center;
    self.world.observers.setPosition(self.observer, self.position.cast(i32));
    self.updateLekoCursor(session.world);
}

fn moveNoclip(self: *Player, session: *Session) void {
    const dt = 1 / session.tick_rate;
    const move_xz = self.getMoveXZ();
    self.hull.center.v[0] += move_xz.v[0] * dt * self.settings.noclip_move_speed;
    self.hull.center.v[1] += self.input.move.v[1] * dt * self.settings.noclip_move_speed;
    self.hull.center.v[2] += move_xz.v[1] * dt * self.settings.noclip_move_speed;
    self.position = self.hull.center;
    self.velocity_y = 0;
    self.is_grounded = false;
}

fn moveNormal(self: *Player, session: *Session) void {
    const world = session.world;
    const dt = 1 / session.tick_rate;
    self.velocity_y -= world.physics.settings.gravity * dt;
    if (world.physics.moveLekoBoundsAxis(&self.hull, self.velocity_y * dt, .y)) |_| {
        defer self.velocity_y = 0;
        if (self.velocity_y < 0) {
            self.is_grounded = true;
        }
    } else {
        self.is_grounded = false;
    }
    if (self.is_grounded and self.input.trigger_jump) {
        self.velocity_y = world.physics.jumpSpeedFromHeight(self.settings.jump_height);
    }
    const move_xz = self.getMoveXZ().mulScalar(dt * self.settings.move_speed);
    self.moveXZ(world, move_xz);
    self.moveStepOffset(dt);
    // self.position = self.hull.center;
    // self.position.v[0] += move_xz.v[0] * dt * self.settings.move_speed;
    // self.position.v[1] += self.input.move.v[1] * dt * self.settings.move_speed;
    // self.position.v[2] += move_xz.v[1] * dt * self.settings.move_speed;
}

fn updateLekoCursor(self: *Player, world: *World) void {
    const physics = &world.physics;
    _ = physics;
    const forward = self.lookMatrix().transpose().transformDirection(Vec3.unit(.z));

    var raycast = Physics.GridRaycastIterator.init(self.eyePosition(), forward);
    self.leko_cursor = null;
    while (raycast.distance < self.settings.interact_range) : (raycast.next()) {
        if (world.leko_data.lekoValueAtPosition(raycast.cell)) |leko_value| {
            if (leko_value != .empty) {
                self.leko_cursor = raycast.cell;
                break;
            }
        } else {
            break;
        }
    }

    // self.leko_cursor = self.eyePosition().add(forward.mulScalar(5)).floor().cast(i32);
}

fn moveXZ(self: *Player, world: *World, move: Vec2) void {
    const physics = &world.physics;
    var step_hull = self.hull; // a temporary hull to use for checking for empty space to step up through
    // move forward, if a collision occurs, see if we can step upwards
    if (moveLekoBoundsXZ(physics, &self.hull, move)) |move_actual| {
        // if we are on the ground, or the ledge we just hit has ground right in front of it,
        // we might be able to step up if there is space.
        // if we are in the air, this will also snap the temporary step hull to that ground
        // right in front of the step
        if (self.is_grounded or physics.moveLekoBoundsAxis(&step_hull, -1, .y) != null) {
            if (physics.moveLekoBoundsAxis(&step_hull, 1, .y) == null) {
                const move_step = moveLekoBoundsXZ(physics, &step_hull, move);
                // zig fmt: off
                if (
                    move_step == null
                    or std.math.fabs(move_step.?.v[0]) > std.math.fabs(move_actual.v[0])
                    or std.math.fabs(move_step.?.v[1]) > std.math.fabs(move_actual.v[1])
                ) {
                // zig fmt: on
                    self.eye_height_offset += self.hull.center.get(.y) - step_hull.center.get(.y);
                    self.hull.center = step_hull.center;
                }
            }
        }
    }
    if (self.is_grounded) {
        step_hull = self.hull;
        if (physics.moveLekoBoundsAxis(&step_hull, -1.1, .y) != null) {
            self.eye_height_offset += self.hull.center.get(.y) - step_hull.center.get(.y);
            self.hull.center = step_hull.center;
        }
    }
}

fn moveLekoBoundsXZ(physics: *Physics, bounds: *Bounds3, move: Vec2) ?Vec2 {
    const x = physics.moveLekoBoundsAxis(bounds, move.v[0], .x);
    const z = physics.moveLekoBoundsAxis(bounds, move.v[1], .z);
    if (x == null and z == null) {
        return null;
    }
    return vec2(.{ x orelse move.v[0], z orelse move.v[1] });
}

fn moveStepOffset(self: *Player, dt: f32) void {
    var offset = self.eye_height_offset;
    if (offset != 0) {
        const offset_delta = self.settings.move_speed * dt * @max(1, std.math.fabs(offset));
        if (offset > 0) {
            offset -= offset_delta;
            if (offset < 0) {
                offset = 0;
            }
        } else {
            offset += offset_delta;
            if (offset > 0) {
                offset = 0;
            }
        }
        self.eye_height_offset = offset;
    }
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
    position.ptrMut(.y).* += self.eye_height + self.eye_height_offset;
    return position;
}

pub fn lookMatrix(self: Player) nm.Mat4 {
    return nm.transform.createEulerZXY(nm.vec3(.{
        -self.look_angles.get(.y) * std.math.pi / 180.0,
        -self.look_angles.get(.x) * std.math.pi / 180.0,
        0,
    }));
}
