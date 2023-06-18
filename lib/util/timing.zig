const std = @import("std");

const Timer = std.time.Timer;

pub const FrameTime = struct {
    timer: Timer,
    last_frame: u64,
    delta_ns: u64 = 0,
    delta_s: f32 = 0,

    pub fn start() !FrameTime {
        return FrameTime{
            .timer = try Timer.start(),
            .last_frame = 0,
        };
    }

    pub fn frame(self: *FrameTime) void {
        const time = self.timer.read();
        self.delta_ns = time - self.last_frame;
        self.delta_s = @intToFloat(f32, self.delta_ns) / std.time.ns_per_s;
    }
};
