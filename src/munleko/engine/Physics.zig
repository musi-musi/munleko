const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const World = @import("World.zig");
const leko = @import("leko.zig");

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;
const Bounds3 = nm.Bounds3;
const Range3i = nm.Range3i;
const Cardinal3 = nm.Cardinal3;
const Axis3 = nm.Axis3;

const Physics = @This();

world: *World,
settings: Settings = .{},

pub const Settings = struct {
    /// gravity strength, in leko/s^2
    gravity: f32 = 40,
};

pub fn init(self: *Physics, world: *World) void {
    self.* = .{
        .world = world,
    };
}

pub fn deinit(self: *Physics) void {
    _ = self;
}

pub fn jumpSpeedFromHeight(self: Physics, height: f32) f32 {
    return @sqrt(2 * self.settings.gravity * height);
}

const LekoType = leko.LekoType;

pub const LekoTypeTest = fn (?LekoType) bool;

pub fn lekoTypeIsSolid(leko_type: ?LekoType) bool {
    if (leko_type) |lt| {
        return lt.properties.is_solid;
    }
    return true;
}

fn invertLekoTypeTest(comptime test_fn: LekoTypeTest) LekoTypeTest {
    return (struct {
        fn f(leko_type: LekoType) bool {
            return !test_fn(leko_type);
        }
    }.f);
}

pub fn testLekoPosition(self: *Physics, position: Vec3i, comptime test_fn: LekoTypeTest) bool {
    const world = self.world;
    const leko_value = world.leko_data.lekoValueAtPosition(position) orelse return test_fn(null);
    const leko_type = world.leko_data.leko_types.getForValue(leko_value);
    return test_fn(leko_type);
}

pub fn testLekoRangeAny(self: *Physics, range: Range3i, comptime test_fn: LekoTypeTest) bool {
    var iter = range.iterate();
    while (iter.next()) |position| {
        if (self.testLekoPosition(position, test_fn)) {
            return true;
        }
    }
    return false;
}

pub fn testLekoRangeAll(self: *Physics, range: Range3i, comptime test_fn: LekoTypeTest) bool {
    return !self.testLekoRangeAny(range, invertLekoTypeTest(test_fn));
}

/// return the distance `bounds` would need to move along `direction` to snap the leading edge to the grid in `direction`
/// distance returned is never negative
pub fn boundsLekoSnapDistance(bounds: Bounds3, comptime direction: Cardinal3) f32 {
    const axis = comptime direction.axis();
    const center = bounds.center.get(axis);
    const radius = bounds.radius.get(axis);
    switch (comptime direction.sign()) {
        .positive => {
            const x = center + radius;
            return @ceil(x) - x;
        },
        .negative => {
            const x = center - radius;
            return x - @floor(x);
        },
    }
}

pub fn moveLekoBoundsAxis(self: *Physics, bounds: *Bounds3, move: f32, comptime axis: Axis3) ?f32 {
    if (move < 0) {
        return self.moveLekoBoundsDirection(bounds, -move, comptime Cardinal3.init(axis, .negative), lekoTypeIsSolid);
    } else {
        return self.moveLekoBoundsDirection(bounds, move, comptime Cardinal3.init(axis, .positive), lekoTypeIsSolid);
    }
}

const skin_width = 1e-3;

fn moveLekoBoundsDirection(self: *Physics, bounds: *Bounds3, move: f32, comptime direction: Cardinal3, comptime is_solid: LekoTypeTest) ?f32 {
    std.debug.assert(move >= 0);
    var distance_moved: f32 = 0;
    const axis = comptime direction.axis();
    const sign = comptime direction.sign();
    const initial_snap = boundsLekoSnapDistance(bounds.*, direction);
    if (initial_snap > move) {
        bounds.center.ptrMut(axis).* += sign.scalar(f32) * move;
        return null;
    }
    bounds.center.ptrMut(axis).* += sign.scalar(f32) * initial_snap;
    distance_moved += initial_snap;
    while (distance_moved < move) {
        if (self.testLekoBoundsDirection(bounds.*, direction, is_solid)) {
            bounds.center.ptrMut(axis).* -= sign.scalar(f32) * skin_width;
            return distance_moved;
        }
        if (move - distance_moved > 1) {
            distance_moved += 1;
            switch (sign) {
                .positive => bounds.center.ptrMut(axis).* += 1,
                .negative => bounds.center.ptrMut(axis).* -= 1,
            }
        } else {
            switch (sign) {
                .positive => bounds.center.ptrMut(axis).* += (move - distance_moved),
                .negative => bounds.center.ptrMut(axis).* -= (move - distance_moved),
            }
            break;
        }
    }
    return null;
}

fn testLekoBoundsDirection(self: *Physics, bounds: Bounds3, comptime direction: Cardinal3, comptime test_fn: LekoTypeTest) bool {
    const range = boundsLekoFaceRange(bounds, direction);
    return self.testLekoRangeAny(range, test_fn);
}

fn boundsLekoFaceRange(bounds: Bounds3, comptime direction: Cardinal3) Range3i {
    const axis = comptime direction.axis();
    const sign = comptime direction.sign();
    const u: Axis3 = switch (axis) {
        .x => .y,
        .y => .x,
        .z => .x,
    };
    const v: Axis3 = switch (axis) {
        .x => .z,
        .y => .z,
        .z => .y,
    };
    var range: Range3i = undefined;
    range.min.ptrMut(u).* = @as(i32, @intFromFloat(@floor(bounds.center.get(u) - bounds.radius.get(u))));
    range.min.ptrMut(v).* = @as(i32, @intFromFloat(@floor(bounds.center.get(v) - bounds.radius.get(v))));
    range.max.ptrMut(u).* = @as(i32, @intFromFloat(@ceil(bounds.center.get(u) + bounds.radius.get(u))));
    range.max.ptrMut(v).* = @as(i32, @intFromFloat(@ceil(bounds.center.get(v) + bounds.radius.get(v))));
    switch (sign) {
        .positive => {
            const x = @as(i32, @intFromFloat(@ceil(bounds.center.get(axis) + bounds.radius.get(axis))));
            range.min.ptrMut(axis).* = x;
            range.max.ptrMut(axis).* = x + 1;
        },
        .negative => {
            const x = @as(i32, @intFromFloat(@floor(bounds.center.get(axis) - bounds.radius.get(axis))));
            range.min.ptrMut(axis).* = x - 1;
            range.max.ptrMut(axis).* = x;
        },
    }
    return range;
}

pub const GridRaycastIterator = struct {
    /// starting position of the ray
    origin: Vec3,
    /// normalized direction of the ray
    direction: Vec3,
    /// the last cell we hit
    cell: Vec3i,
    /// the total distance the raycast has travelled from `origin`
    distance: f32 = 0,
    /// the direction the raycast moved to get to the current cell from the previous cell
    /// null until next is called for the first time
    /// negate this direction to get the normal of the face we just hit
    move: ?Cardinal3 = null,
    // i really dont remember what these two values are exactly but they're part of the state
    // that determines what the next move is
    t_max: Vec3,
    t_delta: Vec3,

    pub fn init(origin: Vec3, direction: Vec3) GridRaycastIterator {
        const dir = direction.norm() orelse Vec3.zero;
        const dx2 = dir.v[0] * dir.v[0];
        const dy2 = dir.v[1] * dir.v[1];
        const dz2 = dir.v[2] * dir.v[2];
        var t_delta = Vec3.zero;
        if (dx2 != 0) t_delta.v[0] = std.math.sqrt(1 + (dy2 + dz2) / dx2);
        if (dy2 != 0) t_delta.v[1] = std.math.sqrt(1 + (dx2 + dz2) / dy2);
        if (dz2 != 0) t_delta.v[2] = std.math.sqrt(1 + (dx2 + dy2) / dz2);
        const origin_floor = origin.floor();
        var t_max = Vec3.init(.{
            (if (dir.v[0] > 0) (origin_floor.v[0] + 1 - origin.v[0]) else origin.v[0] - origin_floor.v[0]) * t_delta.v[0],
            (if (dir.v[1] > 0) (origin_floor.v[1] + 1 - origin.v[1]) else origin.v[1] - origin_floor.v[1]) * t_delta.v[1],
            (if (dir.v[2] > 0) (origin_floor.v[2] + 1 - origin.v[2]) else origin.v[2] - origin_floor.v[2]) * t_delta.v[2],
        });
        if (dir.v[0] == 0) t_max.v[0] = std.math.inf(f32);
        if (dir.v[1] == 0) t_max.v[1] = std.math.inf(f32);
        if (dir.v[2] == 0) t_max.v[2] = std.math.inf(f32);
        return GridRaycastIterator{
            .origin = origin,
            .cell = origin_floor.cast(i32),
            .direction = dir,
            .t_max = t_max,
            .t_delta = t_delta,
        };
    }

    pub fn next(self: *GridRaycastIterator) void {
        const min = self.t_max.minComponent();
        const axis = min.axis;
        self.t_max.ptrMut(axis).* += self.t_delta.get(axis);
        if (self.direction.get(axis) < 0) {
            self.cell.ptrMut(axis).* -= 1;
            self.updateDistance(axis, .negative);
            switch (axis) {
                inline else => |a| self.move = comptime Cardinal3.init(a, .negative),
            }
        } else {
            self.cell.ptrMut(axis).* += 1;
            self.updateDistance(axis, .positive);
            switch (axis) {
                inline else => |a| self.move = comptime Cardinal3.init(a, .positive),
            }
        }
    }

    fn updateDistance(self: *GridRaycastIterator, axis: nm.Axis3, comptime sign: nm.Sign) void {
        var distance = @as(f32, @floatFromInt(self.cell.get(axis))) - self.origin.get(axis);
        distance += (1 - sign.scalar(f32)) / 2;
        self.distance = distance / self.direction.get(axis);
    }
};
