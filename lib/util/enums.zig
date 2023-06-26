const std = @import("std");

pub fn cycleEnum(value: anytype) @TypeOf(value) {
    const E = @TypeOf(value);
    const values = comptime std.enums.values(E);
    const int_value: usize = (@as(usize, @intFromEnum(value)) +% 1) % values.len;
    return @enumFromInt(E, @intCast(std.meta.Tag(E), int_value));
}
