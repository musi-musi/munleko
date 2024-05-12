const std = @import("std");
const nm = @import("nm");

const Session = @import("Session.zig");
const World = @import("World.zig");

const leko = @import("leko.zig");
const Physics = @import("Physics.zig");
const Observer = World.Observer;

const LekoType = leko.LekoType;

const Vec2 = nm.Vec2;
const vec2 = nm.vec2;
const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Bounds3 = nm.Bounds3;

const Cardinal3 = nm.Cardinal3;
const Axis3 = nm.Axis3;

const Player = @This();

world: *World,
observer: Observer,

// Physical states //

position: Vec3,
hull: Bounds3 = .{
    .center = undefined,
    .radius = vec3(.{ 1.5 / 2.0, 3.5 / 2.0, 1.5 / 2.0 }),
},
is_grounded: bool = false,
velocity: Vec3 = Vec3.zero,
eye_height: f32 = 1.5,
eye_height_offset: f32 = 0,
look_angles: Vec2 = Vec2.zero,
move_mode: MoveMode = .normal,

// Leko states //

leko_cursor: ?Vec3i = null,
leko_anchor: ?Vec3i = null,

// corner_cursor: ?Vec3 = null,
/// the leko type to place when placing
leko_equip: ?LekoType = null,
leko_edit_mode: LekoEditMode = .remove,
leko_place_mode: LekoPlaceMode = .normal,

leko_edit_cooldown: i32 = 0,

input: Input = .{},
settings: Settings = .{},
patterns: Patterns = .{},

leko_equip_radial: [leko_equip_radial_len]?LekoType = [1]?LekoType{null} ** leko_equip_radial_len,

pub const leko_equip_radial_len = 8;

pub const Input = struct {
    move: Vec3 = Vec3.zero,
    trigger_jump: bool = false,
    on_primary_pressed: bool = false,
    on_primary_released: bool = false,
    primary: bool = false,
};

pub const Settings = struct {
    stall_speed: f32 = 1.5,
    ground_speed: f32 = 10,
    air_speed: f32 = 2,
    ground_accel: f32 = 80,
    air_accel: f32 = 80,
    ground_friction: f32 = 6,
    air_friction: f32 = 0.1,

    // between 0 and 1, ideally. unless you want to have fun ofc (it will cause error)
    noclip_smoothness: f32 = 0.4,
    eye_move_speed: f32 = 15,
    jump_height: f32 = 2.25,
    noclip_move_speed: f32 = 32,
    interact_range: f32 = 10,
    edit_cooldown_duration: f32 = 0.2,
};

pub const Patterns = struct {
    box: [8]Vec3i = .{
        vec3i(.{ 0, 0, 0 }),
        vec3i(.{ 0, 0, 1 }),
        vec3i(.{ 0, 1, 0 }),
        vec3i(.{ 0, 1, 1 }),
        vec3i(.{ 1, 0, 0 }),
        vec3i(.{ 1, 0, 1 }),
        vec3i(.{ 1, 1, 0 }),
        vec3i(.{ 1, 1, 1 }),
    },
};

pub const MoveMode = enum {
    normal,
    noclip,
};

pub const LekoEditMode = enum {
    remove,
    place,
};

pub const LekoPlaceMode = enum {
    normal,
    wall,
    box,
    drag,
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

pub fn tick(self: *Player, session: *Session) !void {
    defer self.input.trigger_jump = false;
    defer self.input.on_primary_pressed = false;
    defer self.input.on_primary_released = false;
    const dt = 1 / session.tick_timer.rate;
    switch (self.move_mode) {
        .normal => self.moveNormal(session.world, dt),
        .noclip => self.moveNoclip(session.world, dt),
    }
    // self.position = self.hull.center;
    self.hull.center = self.position;
    self.world.observers.setPosition(self.observer, self.position.cast(i32));
    self.updateLekoCursor(session.world);
    if (self.leko_cursor) |cursor| {
        if (self.input.primary and self.leko_edit_cooldown <= 0) {
            self.leko_edit_cooldown = self.editCooldownTicksFromDuration(session);
            switch (self.leko_edit_mode) {
                .remove => _ = try session.world.leko_data.editLekoAtPosition(cursor, .empty),
                .place => switch (self.leko_place_mode) {
                    .box => {
                        if (self.leko_equip) |leko_type| {
                            inline for (self.patterns.box) |offset| {
                                _ = try session.world.leko_data.editLekoAtPosition(cursor.add(offset), leko_type.value);
                            }
                        }
                    },
                    .drag => {},
                    else => {
                        if (self.leko_equip) |leko_type| {
                            _ = try session.world.leko_data.editLekoAtPosition(cursor, leko_type.value);
                        }
                    },
                },
            }
        }
        if (self.input.on_primary_released) {
            if (self.leko_edit_mode == .place and self.leko_place_mode == .drag) {
                if (self.leko_anchor) |anchor| {
                    const dist = cursor.aabbSize(anchor).cast(usize).addScalar(1);
                    if (self.leko_equip) |leko_type| {
                        for (0..dist.get(.x)) |x| {
                            for (0..dist.get(.y)) |y| {
                                for (0..dist.get(.z)) |z| {
                                    const offset = vec3i(.{ @intCast(x), @intCast(y), @intCast(z) });
                                    const target = cursor.min(anchor).add(offset);
                                    if (session.world.leko_data.lekoValueAtPosition(target) == .empty) {
                                        _ = try session.world.leko_data.editLekoAtPosition(target, leko_type.value);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (!self.input.primary) {
        self.leko_anchor = null;
    }
    if (self.leko_edit_cooldown > 0) {
        self.leko_edit_cooldown -= 1;
    }
}

fn editCooldownTicksFromDuration(self: Player, session: *Session) i32 {
    const tick_duration = 1 / session.tick_timer.rate;
    const tick_count: i32 = @intFromFloat(@round(self.settings.edit_cooldown_duration / tick_duration));
    return @max(1, tick_count);
}

fn applyFriction(self: *Player, friction: f32, dt: f32) void {
    const move_vel = vec2(.{ self.velocity.get(.x), self.velocity.get(.z) });
    if (!move_vel.eql(Vec2.zero)) {
        const mag = move_vel.mag();
        const factor = @max(0, mag - @max(mag, self.settings.stall_speed) * friction * dt) / mag;
        self.velocity.v[0] *= factor;
        self.velocity.v[2] *= factor;
    }
}

fn moveForced(self: *Player, dt: f32) void {
    self.position = self.position.add(self.velocity.mulScalar(dt));
}
fn moveAndSlide(self: *Player, world: *World, dt: f32) void {
    if (world.physics.moveLekoBoundsAxis(&self.hull, self.velocity.get(.y) * dt, .y)) |_| {
        defer self.velocity.v[1] = 0;
        if (self.velocity.get(.y) < 0) {
            self.is_grounded = true;
        }
    } else {
        self.is_grounded = false;
    }
    const current_pos = self.position;
    self.moveXZ(world, vec2(.{ self.velocity.get(.x), self.velocity.get(.z) }).mulScalar(dt));
    self.moveStepOffset(dt);
    self.position = self.hull.center;
    const diff = self.position.sub(current_pos).divScalar(dt);
    self.velocity.v[0] = diff.get(.x);
    self.velocity.v[2] = diff.get(.z);
    // self.position = self.hull.center;
    // self.position.v[0] += move_xz.v[0] * dt * self.settings.move_speed;
    // self.position.v[1] += self.input.move.v[1] * dt * self.settings.move_speed;
    // self.position.v[2] += move_xz.v[1] * dt * self.settings.move_speed;
}
fn moveNoclip(self: *Player, _: *World, dt: f32) void {
    const move_xz = self.getMoveXZ();
    const move_dir = vec3(.{ move_xz.get(.x), self.input.move.get(.y), move_xz.get(.y) });
    const target_vel = move_dir.mulScalar(self.settings.noclip_move_speed);
    const t = std.math.pow(f32, self.settings.noclip_smoothness, dt * 60);
    self.velocity = self.velocity.mulScalar(1 - t).add(target_vel.mulScalar(t));

    self.moveForced(dt);
    self.is_grounded = false;
}

fn moveNormal(self: *Player, world: *World, dt: f32) void {
    const speed = if (self.is_grounded) self.settings.ground_speed else self.settings.air_speed;
    const accel = if (self.is_grounded) self.settings.ground_accel else self.settings.air_accel;
    const friction = if (self.is_grounded) self.settings.ground_friction else self.settings.air_friction;
    self.applyFriction(friction, dt);

    const wish_dir = self.getMoveXZ();
    const curr_dir = vec2(.{ self.velocity.get(.x), self.velocity.get(.z) });
    // is there a clamp function
    const real_dir = wish_dir.mulScalar(@min(@max(0, speed - curr_dir.dot(wish_dir)), accel * dt));

    self.velocity.v[0] += real_dir.get(.x);
    self.velocity.v[1] -= world.physics.settings.gravity * dt;
    self.velocity.v[2] += real_dir.get(.y);
    self.moveAndSlide(world, dt);
    if (self.is_grounded and self.input.trigger_jump) {
        self.velocity.v[1] = world.physics.jumpSpeedFromHeight(self.settings.jump_height);
        self.is_grounded = false;
    }
}

fn updateLekoCursor(self: *Player, world: *World) void {
    const physics = &world.physics;
    _ = physics;
    const forward = self.lookMatrix().transpose().transformDirection(Vec3.unit(.z));

    var raycast = Physics.GridRaycastIterator.init(self.eyePosition(), forward);
    self.leko_cursor = null;

    const limit = self.settings.interact_range;
    switch (self.leko_edit_mode) {
        .remove => {
            while (raycast.distance < limit) : (raycast.next()) {
                if (world.leko_data.lekoValueAtPositionIsSolid(raycast.cell)) {
                    self.leko_cursor = raycast.cell;
                    break;
                }
            }
        },
        .place => switch (self.leko_place_mode) {
            .normal => {
                while (raycast.distance < limit) : (raycast.next()) {
                    if (world.leko_data.lekoValueAtPositionIsSolid(raycast.cell)) {
                        if (raycast.move) |move| {
                            const offset = switch (move) {
                                inline else => |m| Vec3i.unitSigned(m),
                            };
                            self.leko_cursor = raycast.cell.sub(offset);
                        }
                        break;
                    }
                }
            },
            .wall => {
                while (raycast.distance < limit) : (raycast.next()) {
                    if (raycast.move != null and checkNeighborsWallPlaceMode(world, raycast.move.?.axis(), raycast.cell)) {
                        self.leko_cursor = raycast.cell;
                        break;
                    }
                }
            },
            .box => {
                while (raycast.distance < limit) : (raycast.next()) {
                    if (world.leko_data.lekoValueAtPositionIsSolid(raycast.cell)) {
                        if (raycast.move) |move| {
                            const offset = switch (move) {
                                inline else => |m| Vec3i.unitSigned(m),
                            };
                            var cursor_target = raycast.cell.sub(offset).sub(raycast.corner);
                            inline for (self.patterns.box) |pattern_offset| {
                                if (world.leko_data.lekoValueAtPosition(cursor_target.add(pattern_offset)) != .empty) {
                                    return;
                                }
                            }
                            self.leko_cursor = cursor_target;
                            // self.corner_cursor = raycast.subcell.cast(f32).divScalar(2);
                        }
                        break;
                    }
                }
            },
            .drag => {
                var air_caught: ?Vec3i = null;
                var solid_dist: ?f32 = null;
                while (raycast.distance < limit) : (raycast.next()) {
                    if (world.leko_data.lekoValueAtPositionIsSolid(raycast.cell)) {
                        if (raycast.move) |move| {
                            const offset = switch (move) {
                                inline else => |m| Vec3i.unitSigned(m),
                            };
                            const offset_cell = raycast.cell.sub(offset);
                            if (self.input.on_primary_pressed) {
                                self.leko_anchor = offset_cell;
                                self.leko_cursor = offset_cell;
                                return;
                            }
                            if (self.leko_anchor == null) {
                                self.leko_cursor = offset_cell;
                                return;
                            }

                            if (self.leko_anchor) |anchor| {
                                if (anchor.eqlAny(offset_cell)) {
                                    self.leko_cursor = offset_cell;
                                    return;
                                }
                            }
                        }
                        if (solid_dist == null) {
                            solid_dist = raycast.distance;
                        }
                    }

                    if (raycast.distance < 0.5) {
                        continue;
                    }
                    if (solid_dist) |dist| {
                        if (raycast.distance > dist + 1) {
                            air_caught = null;
                            break;
                        }
                    }
                    if (air_caught == null) {
                        if (raycast.move != null and raycast.distance < self.settings.interact_range) {
                            if (self.leko_anchor) |anchor| {
                                if (raycast.cell.eqlAny(anchor)) {
                                    air_caught = raycast.cell;
                                }
                            }
                        }
                    }
                }
                self.leko_cursor = air_caught;
            },
        },
    }
}

fn checkNeighborsWallPlaceMode(world: *World, axis: Axis3, cell: Vec3i) bool {
    switch (axis) {
        inline else => |a| {
            const check_list: [4]Cardinal3 = comptime switch (a) {
                .x => [4]Cardinal3{ .y_neg, .y_pos, .z_neg, .z_pos },
                .y => [4]Cardinal3{ .x_neg, .x_pos, .z_neg, .z_pos },
                .z => [4]Cardinal3{ .x_neg, .x_pos, .y_neg, .y_pos },
            };
            inline for (check_list) |dir| {
                const neighbor_cell = cell.add(Vec3i.unitSigned(dir));
                if (world.leko_data.lekoValueAtPosition(neighbor_cell)) |neighbor_value| {
                    if (neighbor_value != .empty) {
                        return true;
                    }
                }
            }
        },
    }
    return false;
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
                    or @abs(move_step.?.v[0]) > @abs(move_actual.v[0])
                    or @abs(move_step.?.v[1]) > @abs(move_actual.v[1])
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
        const offset_delta = self.settings.eye_move_speed * dt * @max(1, @abs(offset));
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
    const face_angle = std.math.degreesToRadians(self.look_angles.v[0]);
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

pub fn eyePositionOffset(self: Player) Vec3 {
    return vec3(.{ 0, self.eye_height + self.eye_height_offset, 0 });
}

pub fn eyePosition(self: Player) Vec3 {
    return self.position.add(self.eyePositionOffset());
}

pub fn lookMatrix(self: Player) nm.Mat4 {
    return nm.transform.createEulerZXY(nm.vec3(.{
        -self.look_angles.get(.y) * std.math.pi / 180.0,
        -self.look_angles.get(.x) * std.math.pi / 180.0,
        0,
    }));
}
