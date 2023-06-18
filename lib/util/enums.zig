const std = @import("std");

pub fn cycleEnum(value: anytype, amount: i32) @TypeOf(value) {
    const E = @TypeOf(value);
    const values = comptime std.enums.values(E);
    return @intToEnum(E, (@enumToInt(value) +% amount) % values.len);
}
