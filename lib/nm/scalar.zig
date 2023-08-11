const std = @import("std");
const nm = @import("lib.zig");

pub fn lerp(comptime T: type, a: T, b: T, t: T) T {
    comptime nm.assertFloat(T);
    return a + ((b - a) * t);
}

pub fn abs(x: anytype) @TypeOf(x) {
    if (x >= 0) {
        return x;
    } else {
        return -x;
    }
}
