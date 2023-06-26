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
    range.min.ptrMut(u).* = @intFromFloat(i32, @floor(bounds.center.get(u) - bounds.radius.get(u)));
    range.min.ptrMut(v).* = @intFromFloat(i32, @floor(bounds.center.get(v) - bounds.radius.get(v)));
    range.max.ptrMut(u).* = @intFromFloat(i32, @ceil(bounds.center.get(u) + bounds.radius.get(u)));
    range.max.ptrMut(v).* = @intFromFloat(i32, @ceil(bounds.center.get(v) + bounds.radius.get(v)));
    switch (sign) {
        .positive => {
            const x = @intFromFloat(i32, @ceil(bounds.center.get(axis) + bounds.radius.get(axis)));
            range.min.ptrMut(axis).* = x;
            range.max.ptrMut(axis).* = x + 1;
        },
        .negative => {
            const x = @intFromFloat(i32, @floor(bounds.center.get(axis) - bounds.radius.get(axis)));
            range.min.ptrMut(axis).* = x - 1;
            range.max.ptrMut(axis).* = x;
        },
    }
    return range;
}
