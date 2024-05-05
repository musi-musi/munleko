const std = @import("std");

pub const AtomicFlag = struct {
    value: bool = false,

    pub fn init(value: bool) AtomicFlag {
        return .{ .raw = value };
    }

    pub fn set(self: *AtomicFlag, value: bool) void {
        @atomicStore(bool, &self.value, value, .monotonic);
    }

    pub fn get(self: *const AtomicFlag) bool {
        return @atomicLoad(bool, &self.value, .monotonic);
    }
};
