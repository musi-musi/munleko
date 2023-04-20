const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;
const Integer = ziglua.Integer;

/// convert table at `index` to a numerical vector
/// return an error if value doesnt have at least `dimensions` array values,
/// or any value cannot be converted to `Scalar`
pub fn toVector(lua: *Lua, comptime Scalar: type, comptime dimensions: comptime_int, index: i32) ![dimensions]Scalar {
    const is_float = comptime std.meta.trait.isFloat(Scalar);
    var vector: [dimensions]Scalar = undefined;
    for (&vector, 0..) |*v, i| {
        _ = lua.getIndex(index, @intCast(Integer, i + 1));
        defer lua.pop(1);
        if (is_float) {
            v.* = @floatCast(Scalar, try lua.toNumber(-1));
        } else {
            v.* = @intCast(Scalar, try lua.toInteger(-1));
        }
    }
    return vector;
}

pub fn toVec2(lua: *Lua, index: i32) ![2]f32 {
    return toVector(lua, f32, 2, index);
}
pub fn toVec3(lua: *Lua, index: i32) ![3]f32 {
    return toVector(lua, f32, 3, index);
}
pub fn toVec4(lua: *Lua, index: i32) ![4]f32 {
    return toVector(lua, f32, 4, index);
}

pub fn toVec2d(lua: *Lua, index: i32) ![2]f64 {
    return toVector(lua, f64, 2, index);
}
pub fn toVec3d(lua: *Lua, index: i32) ![3]f64 {
    return toVector(lua, f64, 3, index);
}
pub fn toVec4d(lua: *Lua, index: i32) ![4]f64 {
    return toVector(lua, f64, 4, index);
}

pub fn toVec2u(lua: *Lua, index: i32) ![2]u32 {
    return toVector(lua, u32, 2, index);
}
pub fn toVec3u(lua: *Lua, index: i32) ![3]u32 {
    return toVector(lua, u32, 3, index);
}
pub fn toVec4u(lua: *Lua, index: i32) ![4]u32 {
    return toVector(lua, u32, 4, index);
}

pub fn toVec2i(lua: *Lua, index: i32) ![2]i32 {
    return toVector(lua, i32, 2, index);
}
pub fn toVec3i(lua: *Lua, index: i32) ![3]i32 {
    return toVector(lua, i32, 3, index);
}
pub fn toVec4i(lua: *Lua, index: i32) ![4]i32 {
    return toVector(lua, i32, 4, index);
}
