const std = @import("std");
const nm = @import("lib.zig");

pub const Cardinal2 = Cardinal(2);
pub const Cardinal3 = Cardinal(3);
pub const Cardinal4 = Cardinal(4);

pub fn Cardinal(comptime dimensions_: comptime_int) type {
    comptime nm.assertValidDimensionCount(dimensions_);
    return switch (dimensions_) {
        1 => enum {
            x_pos,
            x_neg,

            const Self = @This();
            const mixin = Mixin(Self, dimensions_);
            pub usingnamespace mixin;
        },
        2 => enum {
            x_pos,
            x_neg,
            y_pos,
            y_neg,

            const Self = @This();
            const mixin = Mixin(Self, dimensions_);
            pub usingnamespace mixin;
        },
        3 => enum {
            x_pos,
            x_neg,
            y_pos,
            y_neg,
            z_pos,
            z_neg,

            const Self = @This();
            const mixin = Mixin(Self, dimensions_);
            pub usingnamespace mixin;
        },
        4 => enum {
            x_pos,
            x_neg,
            y_pos,
            y_neg,
            z_pos,
            z_neg,
            w_pos,
            w_neg,

            const Self = @This();
            const mixin = Mixin(Self, dimensions_);
            pub usingnamespace mixin;
        },
        else => unreachable,
    };
}

fn Mixin(comptime Self: type, comptime dimensions_: comptime_int) type {
    return struct {
        pub const dimensions = dimensions_;
        pub const Axis = nm.Axis(dimensions);
        const AxisTag = std.meta.Tag(Axis);

        pub fn init(a: Axis, s: Sign) Self {
            return @as(Self, @enumFromInt(@as(u32, @intCast(@intFromEnum(a))) * 2 + @intFromEnum(s)));
        }

        pub fn axis(self: Self) Axis {
            return @as(Axis, @enumFromInt(@as(AxisTag, @truncate(@intFromEnum(self) >> 1))));
        }

        pub fn sign(self: Self) Sign {
            return @as(Sign, @enumFromInt(@as(u1, @truncate(@intFromEnum(self) % 2))));
        }

        pub fn negate(self: Self) Self {
            return @as(Self, @enumFromInt(@intFromEnum(self) ^ 1));
        }
    };
}

pub const Sign = enum(u1) {
    positive,
    negative,

    pub fn ofScalar(comptime T: type, value: T) Sign {
        if (value > 0) {
            return .positive;
        } else {
            return .negative;
        }
    }

    pub fn scalar(sign: Sign, comptime T: type) T {
        return switch (sign) {
            .positive => 1,
            .negative => -1,
        };
    }
};
