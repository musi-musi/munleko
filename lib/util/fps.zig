const std = @import("std");

const Timer = std.time.Timer;

pub const FpsCounter = struct {
    timer: Timer,
    frame_count: u32 = 0,
    /// time between updates, in s
    read_delay: f32 = 1,

    pub fn start(read_delay: f32) !FpsCounter {
        return FpsCounter {
            .timer = try Timer.start(),
            .read_delay = read_delay,
        };
    }

    pub fn tick(self: *FpsCounter) ?f32 {
        const read_delay_ns = @floatToInt(u64, self.read_delay * std.time.ns_per_s);
        var time = self.timer.read();
        if (time > read_delay_ns) {
            self.timer.reset();
            const fps = @intToFloat(f32, self.frame_count) / self.read_delay;
            self.frame_count = 1;
            return fps;
        }
        else {
            self.frame_count += 1;
            return null;
        }
    }

};