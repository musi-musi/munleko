const std = @import("std");

const nm = @import("lib.zig");

pub const Vec2 = Vector(f32, 2);
pub const Vec3 = Vector(f32, 3);
pub const Vec4 = Vector(f32, 4);

pub fn vec2(v: Vec2.Value) Vec2 {
    return Vec2.init(v);
}
pub fn vec3(v: Vec3.Value) Vec3 {
    return Vec3.init(v);
}
pub fn vec4(v: Vec4.Value) Vec4 {
    return Vec4.init(v);
}

pub const Vec2d = Vector(f64, 2);
pub const Vec3d = Vector(f64, 3);
pub const Vec4d = Vector(f64, 4);

pub fn vec2d(v: Vec2d.Value) Vec2d {
    return Vec2d.init(v);
}
pub fn vec3d(v: Vec3d.Value) Vec3d {
    return Vec3d.init(v);
}
pub fn vec4d(v: Vec4d.Value) Vec4d {
    return Vec4d.init(v);
}

pub const Vec2i = Vector(i32, 2);
pub const Vec3i = Vector(i32, 3);
pub const Vec4i = Vector(i32, 4);

pub fn vec2i(v: Vec2i.Value) Vec2i {
    return Vec2i.init(v);
}
pub fn vec3i(v: Vec3i.Value) Vec3i {
    return Vec3i.init(v);
}
pub fn vec4i(v: Vec4i.Value) Vec4i {
    return Vec4i.init(v);
}

pub const Vec2u = Vector(u32, 2);
pub const Vec3u = Vector(u32, 3);
pub const Vec4u = Vector(u32, 4);

pub fn vec2u(v: Vec2u.Value) Vec2u {
    return Vec2u.init(v);
}
pub fn vec3u(v: Vec3u.Value) Vec3u {
    return Vec3u.init(v);
}
pub fn vec4u(v: Vec4u.Value) Vec4u {
    return Vec4u.init(v);
}

pub fn Vector(comptime Scalar_: type, comptime dimensions_: comptime_int) type {
    comptime nm.assertFloatOrInt(Scalar_);
    comptime nm.assertValidDimensionCount(dimensions_);
    return extern struct {
        v: Value,

        pub const Value = [dimensions]Scalar;
        pub const Scalar = Scalar_;
        pub const dimensions = dimensions_;

        pub const Axis = nm.Axis(dimensions);
        pub const Cardinal = nm.Cardinal(dimensions);

        pub const axes = Axis.values;
        pub const indices = ([4]u32{ 0, 1, 2, 3 })[0..dimensions];

        pub const Comp = switch (dimensions) {
            1 => extern struct {
                x: Scalar,
            },
            2 => extern struct {
                x: Scalar,
                y: Scalar,
            },
            3 => extern struct {
                x: Scalar,
                y: Scalar,
                z: Scalar,
            },
            4 => extern struct {
                x: Scalar,
                y: Scalar,
                z: Scalar,
                w: Scalar,
            },
            else => unreachable,
        };

        const Self = @This();

        pub const zero = fill(0);
        pub const one = fill(1);

        pub fn init(v: Value) Self {
            return .{ .v = v };
        }

        pub fn get(self: Self, a: Axis) Scalar {
            return self.v[@intFromEnum(a)];
        }
        pub fn set(self: *Self, a: Axis, v: Scalar) void {
            self.v[@intFromEnum(a)] = v;
        }
        pub fn ptr(self: *const Self, a: Axis) *const Scalar {
            return &(self.v[@intFromEnum(a)]);
        }
        pub fn ptrMut(self: *Self, a: Axis) *Scalar {
            return &(self.v[@intFromEnum(a)]);
        }

        pub fn cast(self: Self, comptime S: type) Vector(S, dimensions) {
            var result: Vector(S, dimensions) = undefined;
            inline for (indices) |i| {
                switch (@typeInfo(Scalar)) {
                    .Float => switch (@typeInfo(S)) {
                        .Float => result.v[i] = @as(S, @floatCast(self.v[i])),
                        .Int => result.v[i] = @as(S, @intFromFloat(self.v[i])),
                        else => unreachable,
                    },
                    .Int => switch (@typeInfo(S)) {
                        .Float => result.v[i] = @as(S, @floatFromInt(self.v[i])),
                        .Int => result.v[i] = @as(S, @intCast(self.v[i])),
                        else => unreachable,
                    },
                    else => unreachable,
                }
            }
            return result;
        }

        /// lower this vector by one dimension, discarding last component
        pub fn removeDimension(self: Self) Vector(Scalar, dimensions - 1) {
            return Vector(Scalar, dimensions - 1).init(self.v[0..(dimensions - 1)].*);
        }

        /// raise this vector by one dimension, appending v as the value for the last component
        pub fn addDimension(self: Self, v: Scalar) Vector(Scalar, dimensions + 1) {
            const Target = Vector(Scalar, dimensions + 1);
            var res: Target = undefined;
            inline for (indices) |i| {
                res.v[i] = self.v[i];
            }
            res.v[dimensions] = v;
            return res;
        }

        pub fn toAffinePosition(self: Self) Vector(Scalar, dimensions + 1) {
            return self.addDimension(1);
        }
        pub fn toAffineDirection(self: Self) Vector(Scalar, dimensions + 1) {
            return self.addDimension(0);
        }

        pub fn fill(v: Scalar) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = v;
            }
            return res;
        }

        pub fn unit(comptime a: Axis) Self {
            return comptime blk: {
                var res = fill(0);
                res.set(a, 1);
                break :blk res;
            };
        }

        pub fn unitSigned(comptime c: Cardinal) Self {
            return comptime blk: {
                break :blk switch (c.sign()) {
                    .positive => unit(c.axis()),
                    .negative => unit(c.axis()).neg(),
                };
            };
        }

        pub const Component = struct {
            value: Scalar,
            axis: Axis,
        };

        pub fn minComponent(self: Self) Component {
            var component = Component{
                .value = self.v[0],
                .axis = Axis.x,
            };
            inline for (comptime std.enums.values(Axis)[1..]) |axis| {
                const v = self.get(axis);
                if (v < component.value) {
                    component.value = v;
                    component.axis = axis;
                }
            }
            return component;
        }

        pub fn maxComponent(self: Self) Component {
            var component = Component{
                .value = self.v[0],
                .axis = Axis.x,
            };
            inline for (comptime std.enums.values(Axis)[1..]) |axis| {
                const v = self.get(axis);
                if (v > component.value) {
                    component.value = v;
                    component.axis = axis;
                }
            }
            return component;
        }

        pub fn eql(a: Self, b: Self) bool {
            inline for (indices) |i| {
                if (a.v[i] != b.v[i]) {
                    return false;
                }
            }
            return true;
        }

        pub fn abs(self: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = nm.abs(self.v[i]);
            }
            return res;
        }

        /// unary negation
        pub fn neg(self: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = -self.v[i];
            }
            return res;
        }

        /// component-wise floor
        pub fn floor(self: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = std.math.floor(self.v[i]);
            }
            return res;
        }

        /// component-wise ceil
        pub fn ceil(self: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = std.math.ceil(self.v[i]);
            }
            return res;
        }

        /// component-wise round
        pub fn round(self: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = std.math.round(self.v[i]);
            }
            return res;
        }

        /// component-wise addition
        pub fn add(a: Self, b: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = a.v[i] + b.v[i];
            }
            return res;
        }

        /// component-wise subtraction
        pub fn sub(a: Self, b: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = a.v[i] - b.v[i];
            }
            return res;
        }

        /// component-wise multiplication
        pub fn mul(a: Self, b: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = a.v[i] * b.v[i];
            }
            return res;
        }

        /// component-wise division
        pub fn div(a: Self, b: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = a.v[i] / b.v[i];
            }
            return res;
        }

        /// scalar addition
        pub fn addScalar(a: Self, b: Scalar) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = a.v[i] + b;
            }
            return res;
        }

        /// scalar subtraction
        pub fn subScalar(a: Self, b: Scalar) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = a.v[i] - b;
            }
            return res;
        }

        /// scalar multiplication
        pub fn mulScalar(a: Self, b: Scalar) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = a.v[i] * b;
            }
            return res;
        }

        /// scalar division
        pub fn divScalar(a: Self, b: Scalar) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = a.v[i] / b;
            }
            return res;
        }

        /// scalar floor division
        /// only valid for signed integers
        pub fn divFloorScalar(a: Self, b: Scalar) Self {
            comptime nm.assertInt(Scalar);
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = @divFloor(a.v[i], b);
            }
            return res;
        }

        /// sum of components
        pub fn sum(self: Self) Scalar {
            var res: Scalar = 0;
            inline for (indices) |i| {
                res += self.v[i];
            }
            return res;
        }

        /// product of components
        pub fn product(self: Self) Scalar {
            var res: Scalar = 0;
            inline for (indices) |i| {
                res *= self.v[i];
            }
            return res;
        }

        /// dot product
        pub fn dot(a: Self, b: Self) Scalar {
            return a.mul(b).sum();
        }

        /// square magnitude
        pub fn mag2(self: Self) Scalar {
            return self.dot(self);
        }

        /// magnitude
        pub fn mag(self: Self) Scalar {
            return std.math.sqrt(self.mag2());
        }

        /// normalized
        pub fn norm(self: Self) ?Self {
            const m = self.mag();
            if (m == 0) {
                return null;
            } else {
                return self.divScalar(self.mag());
            }
        }

        pub fn lerpTo(self: Self, target: Self, t: Scalar) Self {
            comptime nm.assertFloat(Scalar);
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = nm.lerp(Scalar, self.v[i], target.v[i], t);
            }
            return res;
        }

        /// cross product
        /// using with non-3d vectors is a compile error
        pub fn cross(a: Self, b: Self) Self {
            if (dimensions != 3) @compileError("cannot compute cross product of non 3d vectors");
            var res: Self = undefined;
            res.v[0] = a.v[1] * b.v[2] - a.v[2] * b.v[1];
            res.v[1] = a.v[2] * b.v[0] - a.v[0] * b.v[2];
            res.v[2] = a.v[0] * b.v[1] - a.v[1] * b.v[0];
            return res;
        }

        /// component-wise check for any equal values
        pub fn eqlAny(a: Self, b: Self) bool {
            inline for (indices) |i| {
                if (a.v[i] == b.v[i]) {
                    return true;
                }
            }
            return false;
        }

        /// component-wise @min
        pub fn min(a: Self, b: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = @min(a.v[i], b.v[i]);
            }
            return res;
        }

        /// component-wise @max
        pub fn max(a: Self, b: Self) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = @max(a.v[i], b.v[i]);
            }
            return res;
        }

        /// difference between max() of two vectors and min() of those same vectors
        pub fn aabbSize(a: Self, b: Self) Self {
            return a.max(b).sub(a.min(b));
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, w: anytype) !void {
            try w.writeAll("(");
            inline for (indices) |i| {
                if (i != 0) {
                    try w.writeAll(", ");
                }
                try std.fmt.formatType(self.v[i], fmt, options, w, 1);
            }
            try w.writeAll(")");
        }

        pub fn project(self: Self, target: Self) Self {
            comptime nm.assertFloat(Scalar);
            return target.mul(self.dot(target) / target.dot(target));
        }

        pub fn scalarProject(self: Self, target: Self) Scalar {
            comptime nm.assertFloat(Scalar);
            return self.dot(target) / target.mag();
        }

        pub fn clampScalar(self: Self, a: Scalar, b: Scalar) Self {
            var res: Self = undefined;
            inline for (indices) |i| {
                res.v[i] = std.math.clamp(self.v[i], a, b);
            }
            return res;
        }
    };
}
