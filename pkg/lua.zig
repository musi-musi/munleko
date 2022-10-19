const std = @import("std");
const c = @import("lua/c.zig");

const Allocator = std.mem.Allocator;

pub const StatePtr = ?*c.lua_State;

const Vptr = ?*anyopaque;


pub const State = struct {
    ptr: StatePtr = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator) State {
        return .{
            .allocator = allocator,
        };
    }

    pub fn create(self: *State) !void {
        if (c.lua_newstate(allocFn, self)) |ptr| {
            self.ptr = ptr;
        }
        else {
            return error.LuaStateCreationFailed;
        }
    }

    pub fn destroy(self: State) void {
        c.lua_close(self.ptr);
    }

    fn allocFn(ud: Vptr, c_ptr: Vptr, old_len: usize, new_len: usize) callconv(.C) Vptr {
        const self = @ptrCast(*State, ud.?);
        const allocator = self.allocator;
        if (c_ptr) |ptr| {
            const slice = @ptrCast([*]u8, ptr)[0..old_len];
            if (new_len == 0) {
                allocator.free(slice);
                return null;
            }
            else {
                return allocator.resize(slice, new_len) catch null;
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