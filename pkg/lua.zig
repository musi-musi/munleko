const std = @import("std");
const c = @import("lua/c.zig");

const Allocator = std.mem.Allocator;

pub const StatePtr = ?*c.lua_State;

const Vptr = ?*anyopaque;

pub const LuaType = enum(c_int) {
    none = c.LUA_TNONE,
    nil = c.LUA_TNIL,
    boolean = c.LUA_TBOOLEAN,
    light_user = c.LUA_TLIGHTUSERDATA,
    number = c.LUA_TNUMBER,
    string = c.LUA_TSTRING,
    table = c.LUA_TTABLE,
    function = c.LUA_TFUNCTION,
    user = c.LUA_TUSERDATA,
    thread = c.LUA_TTHREAD,
};

pub const Function = fn(*State) anyerror!u32;


pub const State = struct {
    ptr: StatePtr = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator) State {
        return .{
            .allocator = allocator,
        };
    }

    pub fn create(self: *State) !void {
        if (c.lua_newstate(&allocFn, self)) |ptr| {
            self.ptr = ptr;
        }
        else {
            return error.LuaStateCreationFailed;
        }
    }

    pub fn destroy(self: State) void {
        c.lua_close(self.ptr);
    }

    fn getSelf(ptr: StatePtr) *State {
        var ud: Vptr = null;
        _ = c.lua_getallocf(ptr, &ud);
        return @ptrCast(*State, @alignCast(@alignOf(State), ud.?));
    }

    pub fn absIndex(self: *State, i: i32) i32 {
        return @intCast(i32, c.lua_absindex(self.ptr, @intCast(c_int, i)));
    }

    /// its good practice to call this before using the stack, in order to catch allocation failure
    pub fn checkStack(self: *State, cap: usize) Allocator.Error!void {
        if (c.lua_checkstack(self.ptr, @intCast(c_int, cap)) == 0) {
            return Allocator.Error.OutOfMemory;
        }
    }

    pub fn copy(self: *State, from: i32, to: i32) void {
        c.lua_copy(self.ptr, @intCast(c_int, from), @intCast(c_int, to));
    }

    pub fn setTop(self: *State, i: i32) void {
        c.lua_settop(self.ptr, @intCast(c_int, i));
    }

    pub fn pop(self: *State, n: i32) void {
        c.lua_pop(self.ptr, @intCast(c_int, n));
    }

    pub fn pushNil(self: *State) void {
        c.lua_pushnil(self.ptr);
    }

    pub fn pushBool(self: *State, b: bool) void {
        if (b) {
            c.lua_pushboolean(self.ptr, 1);
        }
        else {
            c.lua_pushboolean(self.ptr, 0);
        }
    }

    pub fn pushNumber(self: *State, comptime T: type, x: T) void {
        switch (@typeInfo(T)) {
            .Int, .ComptimeInt => c.lua_pushinteger(self.ptr, @intCast(c_long, x)),
            .Float, .ComptimeFloat => c.lua_pushnumber(self.ptr, @intCast(f64, x)),
            else => @compileError(@typeName(T) ++ " is not a numeric type"),
        }
    }

    pub fn pushLightUser(self: *State, comptime T: type, p: *const T) void {
        c.lua_pushlightuserdata(self.ptr, @ptrCast(Vptr, p));
    }

    pub fn pushString(self: *State, s: []const u8) Allocator.Error![]const u8 {
        if (c.lua_pushlstring(self.ptr, s.ptr, s.len)) |ptr| {
            return ptr[0..s.len];
        }
        else {
            return error.OutOfMemory;
        }
    }

    pub fn pushClosure(self: *State, comptime func: Function, upvalue_count: u32) void {
        const S = struct {
            fn f(ptr: StatePtr) callconv(.C) c_int {
                const s = getSelf(ptr);
                const results = func(s) catch |err| {
                    s.pushNumber(u64, @errorToInt(err));
                    return c.lua_error(ptr);
                };
                return @intCast(c_int, results);
            }
        };
        c.lua_pushcclosure(self.ptr, &S.f, @intCast(c_int, upvalue_count));
    }

    pub fn pushFunction(self: *State, comptime func: Function) void {
        return self.pushClosure(func, 0);
    }

    pub fn newTable(self: *State, narr: usize, nrec: usize) void {
        c.lua_createtable(self.ptr, @intCast(c_int, narr), @intCast(c_int, nrec));
    }

    pub fn luaType(self: *State, i: i32) LuaType {
        const t = c.lua_type(self.ptr, @intCast(c_int, i));
        return @intToEnum(LuaType, t);
    }


    fn allocFn(ud: Vptr, c_ptr: Vptr, old_len: usize, new_len: usize) callconv(.C) Vptr {
        const self = @ptrCast(*State, @alignCast(@alignOf(State), ud.?));
        const allocator = self.allocator;
        if (c_ptr) |ptr| {
            const slice = @ptrCast([*]u8, ptr)[0..old_len];
            if (new_len == 0) {
                allocator.free(slice);
                return null;
            }
            else {
                if (allocator.resize(slice, new_len)) |new| {
                    return @ptrCast(Vptr, new.ptr);
                }
                else {
                    return null;
                }
            }
        }
        else {
            if (new_len == 0) {
                return null;
            }
            else {
                const slice = allocator.alloc(u8, new_len) catch return null;
                return @ptrCast(Vptr, slice.ptr);
            }
        }
    }
};