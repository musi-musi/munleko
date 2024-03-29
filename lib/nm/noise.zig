const std = @import("std");
const nm = @import("lib.zig");

pub const Perlin1 = Perlin(f32, 1);
pub const Perlin2 = Perlin(f32, 2);
pub const Perlin3 = Perlin(f32, 3);
pub const Perlin4 = Perlin(f32, 4);
pub const Perlin1d = Perlin(f64, 1);
pub const Perlin2d = Perlin(f64, 2);
pub const Perlin3d = Perlin(f64, 3);
pub const Perlin4d = Perlin(f64, 4);

pub fn Perlin(comptime Scalar_: type, comptime dimensions_: u32) type {
    comptime nm.assertFloat(Scalar_);
    comptime nm.assertValidDimensionCount(dimensions_);
    return struct {
        pub const Scalar = Scalar_;
        pub const dimensions = dimensions_;

        pub const Vector = nm.Vector(Scalar, dimensions);
        pub const IVector = nm.Vector(isize, dimensions);

        const Self = @This();

        const gradient_table = blk: {
            @setEvalBranchQuota(100000);
            var result: [548]Vector = undefined;
            var rng = std.rand.DefaultPrng.init(0x983546);
            const r = rng.random();
            var v = 0;
            while (v < result.len) : (v += 1) {
                var g: Vector = undefined;
                for (Vector.indices) |i| {
                    g.v[i] = (r.float(Scalar) * 2) - 1;
                }
                if (dimensions > 1) {
                    var mag: Scalar = 0;
                    for (Vector.indices) |i| {
                        mag += g.v[i] * g.v[i];
                    }
                    mag = std.math.sqrt(mag);
                    for (Vector.indices) |i| {
                        g.v[i] /= mag;
                    }
                    result[v] = g;
                }
            }
            break :blk result;
        };

        pub fn sample(self: Self, value: Vector.Value) Scalar {
            _ = self;
            var v = Vector.init(value);
            const min: IVector = v.floor().cast(isize);
            const max = min.add(IVector.fill(1));
            const a = min.v;
            const b = max.v;
            const s = v.sub(min.cast(Scalar)).v;
            switch (dimensions) {
                1 => {
                    return interpolate(dotGradient(.{a[0]}, v), dotGradient(.{b[0]}, v), s[0]);
                },
                2 => {
                    return interpolate(interpolate(dotGradient(.{ a[0], a[1] }, v), dotGradient(.{ b[0], a[1] }, v), s[0]), interpolate(dotGradient(.{ a[0], b[1] }, v), dotGradient(.{ b[0], b[1] }, v), s[0]), s[1]);
                },
                3 => {
                    return interpolate(interpolate(interpolate(dotGradient(.{ a[0], a[1], a[2] }, v), dotGradient(.{ b[0], a[1], a[2] }, v), s[0]), interpolate(dotGradient(.{ a[0], b[1], a[2] }, v), dotGradient(.{ b[0], b[1], a[2] }, v), s[0]), s[1]), interpolate(interpolate(dotGradient(.{ a[0], a[1], b[2] }, v), dotGradient(.{ b[0], a[1], b[2] }, v), s[0]), interpolate(dotGradient(.{ a[0], b[1], b[2] }, v), dotGradient(.{ b[0], b[1], b[2] }, v), s[0]), s[1]), s[2]);
                },
                4 => {
                    return interpolate(interpolate(interpolate(interpolate(dotGradient(.{ a[0], a[1], a[2], a[3] }, v), dotGradient(.{ b[0], a[1], a[2], a[3] }, v), s[0]), interpolate(dotGradient(.{ a[0], b[1], a[2], a[3] }, v), dotGradient(.{ b[0], b[1], a[2], a[3] }, v), s[0]), s[1]), interpolate(interpolate(dotGradient(.{ a[0], a[1], b[2], a[3] }, v), dotGradient(.{ b[0], a[1], b[2], a[3] }, v), s[0]), interpolate(dotGradient(.{ a[0], b[1], b[2], a[3] }, v), dotGradient(.{ b[0], b[1], b[2], a[3] }, v), s[0]), s[1]), s[2]), interpolate(interpolate(interpolate(dotGradient(.{ a[0], a[1], a[2], b[3] }, v), dotGradient(.{ b[0], a[1], a[2], b[3] }, v), s[0]), interpolate(dotGradient(.{ a[0], b[1], a[2], b[3] }, v), dotGradient(.{ b[0], b[1], a[2], b[3] }, v), s[0]), s[1]), interpolate(interpolate(dotGradient(.{ a[0], a[1], b[2], b[3] }, v), dotGradient(.{ b[0], a[1], b[2], b[3] }, v), s[0]), interpolate(dotGradient(.{ a[0], b[1], b[2], b[3] }, v), dotGradient(.{ b[0], b[1], b[2], b[3] }, v), s[0]), s[1]), s[2]), s[3]);
                },
                else => unreachable,
            }
        }

        fn interpolate(a: Scalar, b: Scalar, t: Scalar) Scalar {
            return (b - a) * (3 - t * 2) * t * t + a;
        }

        fn dotGradient(value: [dimensions]isize, position: Vector) Scalar {
            const grad = gradient(value);
            var dist: Vector = undefined;
            inline for (Vector.indices) |i| {
                dist.v[i] = @as(Scalar, @floatFromInt(value[i])) - position.v[i];
            }
            return dist.dot(grad);
        }

        fn gradient(value: [dimensions]isize) Vector {
            comptime var rng = std.rand.DefaultPrng.init(0);
            const r = comptime rng.random();
            var hash = comptime r.int(usize);
            comptime var i = 0;
            inline while (i < dimensions) : (i += 1) {
                hash ^= (@as(usize, @bitCast(value[i])) << 5 * i) ^ comptime r.int(usize) +% r.int(usize);
                hash ^= (@as(usize, @bitCast(value[i])) << 2 * i + 3) ^ comptime r.int(usize) +% r.int(usize);
                hash ^= (@as(usize, @bitCast(value[i])) << i + 6) ^ comptime r.int(usize) +% r.int(usize);
            }
            return gradient_table[hash % gradient_table.len];
        }
    };
}
