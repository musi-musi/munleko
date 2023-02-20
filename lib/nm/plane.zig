const std = @import("std");
const nm = @import("lib.zig");


pub const Plane2 = Plane(f32, 2);
pub const Plane3 = Plane(f32, 3);
pub const Plane4 = Plane(f32, 4);

pub const Plane2d = Plane(f64, 2);
pub const Plane3d = Plane(f64, 3);
pub const Plane4d = Plane(f64, 4);

pub const plane2 = Plane2.init;
pub const plane3 = Plane3.init;
pub const plane4 = Plane4.init;

pub const plane2d = Plane2d.init;
pub const plane3d = Plane3d.init;
pub const plane4d = Plane4d.init;

pub fn Plane(comptime Scalar_: type, comptime dimensions_: comptime_int) type {
    comptime nm.assertFloat(Scalar_);
    comptime nm.assertValidDimensionCount(dimensions_);
    return extern struct {
        normal: Vector,
        distance: Scalar,

        pub const Scalar = Scalar_;
        pub const dimensions = dimensions_;

        pub const Vector = nm.Vector(Scalar, dimensions);

        const Self = @This();

        pub fn init(normal: Vector, distance: Scalar) Self {
            return Self {
                .normal = normal,
                .distance = distance,
            };
        }

        pub fn pointIsAbove(self: Self, position: Vector) bool {
            return self.pointSignedDistance(position) > 0;
        }
        pub fn pointIsAboveAssumeUnitNormal(self: Self, position: Vector) bool {
            return self.pointSignedDistanceAssumeUnitNormal(position) > 0;
        }

        pub fn pointSignedDistance(self: Self, position: Vector) Scalar {
            return position.scalarProject(self.normal) - self.distance;
        }
        /// signed distance from position to the plane. assumes self.normal is a unit vector
        pub fn pointSignedDistanceAssumeUnitNormal(self: Self, position: Vector) Scalar {
            return position.dot(self.normal) - self.distance;
        }
    };
}
