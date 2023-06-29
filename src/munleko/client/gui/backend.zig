const std = @import("std");
const zgui = @import("zgui");
const window = @import("window");

const Window = window.Window;

pub const Platform = struct {
    window: *Window,
    time: f32,

    pub fn init(win: *Window) Platform {
        return .{
            .window = win,
            .time = @floatCast(f32, win.getTime()),
        };
    }

    pub fn deinit(self: *Platform) void {
        _ = self;
    }

    pub fn startFrame(self: *Platform) void {
        const time = @floatCast(f32, self.window.getTime());
        zgui.io.setDeltaTime(time - self.time);
        self.time = time;
        zgui.io.setDisplaySize(@floatFromInt(f32, self.window.size[0]), @floatFromInt(f32, self.window.size[1]));
        for (self.window.events.get(.focus)) |focus| {
            zgui.io.addFocusEvent(focus == .focused);
        }

        zgui.io.addKeyEvent(.mod_ctrl, self.window.buttonHeld(.left_control) or self.window.buttonHeld(.right_control));
        zgui.io.addKeyEvent(.mod_shift, self.window.buttonHeld(.left_shift) or self.window.buttonHeld(.right_shift));
        zgui.io.addKeyEvent(.mod_alt, self.window.buttonHeld(.left_alt) or self.window.buttonHeld(.right_alt));
        zgui.io.addKeyEvent(.mod_super, self.window.buttonHeld(.left_super) or self.window.buttonHeld(.right_super));

        const f32_max = comptime std.math.floatMax(f32);
        switch (self.window.mouse_mode) {
            .disabled => zgui.io.addMousePositionEvent(-f32_max, -f32_max),
            else => {
                const mouse_position = self.window.mousePosition();
                zgui.io.addMousePositionEvent(mouse_position[0], mouse_position[1]);
            },
        }

        for (self.window.events.get(.mouse_enter)) |mouse_enter| {
            if (mouse_enter == .exited) {
                zgui.io.addMousePositionEvent(-f32_max, -f32_max);
            }
        }

        for (self.window.events.get(.button_pressed)) |code| {
            switch (code) {
                .mouse_1 => zgui.io.addMouseButtonEvent(.left, true),
                .mouse_2 => zgui.io.addMouseButtonEvent(.right, true),
                .mouse_3 => zgui.io.addMouseButtonEvent(.middle, true),
                else => {
                    if (keyFromButtonCode(code)) |key| {
                        zgui.io.addKeyEvent(key, true);
                    }
                },
            }
        }
        for (self.window.events.get(.button_released)) |code| {
            switch (code) {
                .mouse_1 => zgui.io.addMouseButtonEvent(.left, false),
                .mouse_2 => zgui.io.addMouseButtonEvent(.right, false),
                .mouse_3 => zgui.io.addMouseButtonEvent(.middle, false),
                else => {
                    if (keyFromButtonCode(code)) |key| {
                        zgui.io.addKeyEvent(key, false);
                    }
                },
            }
        }
        for (self.window.events.get(.scroll)) |scroll| {
            zgui.io.addMouseWheelEvent(scroll[0], scroll[1]);
        }
        for (self.window.events.get(.character_input)) |char| {
            zgui.io.addCharacterEvent(@intCast(i32, char));
        }
    }

    fn keyFromButtonCode(code: window.ButtonCode) ?zgui.Key {
        return switch (code) {
            .space => zgui.Key.space,
            .apostrophe => zgui.Key.apostrophe,
            .comma => zgui.Key.comma,
            .minus => zgui.Key.minus,
            .period => zgui.Key.period,
            .slash => zgui.Key.slash,
            .alpha_0 => zgui.Key.zero,
            .alpha_1 => zgui.Key.one,
            .alpha_2 => zgui.Key.two,
            .alpha_3 => zgui.Key.three,
            .alpha_4 => zgui.Key.four,
            .alpha_5 => zgui.Key.five,
            .alpha_6 => zgui.Key.six,
            .alpha_7 => zgui.Key.seven,
            .alpha_8 => zgui.Key.eight,
            .alpha_9 => zgui.Key.nine,
            .semicolon => zgui.Key.semicolon,
            .equal => zgui.Key.equal,
            .a => zgui.Key.a,
            .b => zgui.Key.b,
            .c => zgui.Key.c,
            .d => zgui.Key.d,
            .e => zgui.Key.e,
            .f => zgui.Key.f,
            .g => zgui.Key.g,
            .h => zgui.Key.h,
            .i => zgui.Key.i,
            .j => zgui.Key.j,
            .k => zgui.Key.k,
            .l => zgui.Key.l,
            .m => zgui.Key.m,
            .n => zgui.Key.n,
            .o => zgui.Key.o,
            .p => zgui.Key.p,
            .q => zgui.Key.q,
            .r => zgui.Key.r,
            .s => zgui.Key.s,
            .t => zgui.Key.t,
            .u => zgui.Key.u,
            .v => zgui.Key.v,
            .w => zgui.Key.w,
            .x => zgui.Key.x,
            .y => zgui.Key.y,
            .z => zgui.Key.z,
            .left_bracket => zgui.Key.left_bracket,
            .backslash => zgui.Key.back_slash,
            .right_bracket => zgui.Key.right_bracket,
            .grave => zgui.Key.grave_accent,
            .escape => zgui.Key.escape,
            .enter => zgui.Key.enter,
            .tab => zgui.Key.tab,
            .backspace => zgui.Key.back_space,
            .insert => zgui.Key.insert,
            .delete => zgui.Key.delete,
            .right => zgui.Key.right_arrow,
            .left => zgui.Key.left_arrow,
            .down => zgui.Key.down_arrow,
            .up => zgui.Key.up_arrow,
            .page_up => zgui.Key.page_up,
            .page_down => zgui.Key.page_down,
            .home => zgui.Key.home,
            .end => zgui.Key.end,
            .caps_lock => zgui.Key.caps_lock,
            .scroll_lock => zgui.Key.scroll_lock,
            .num_lock => zgui.Key.num_lock,
            .print_screen => zgui.Key.print_screen,
            .pause => zgui.Key.pause,
            .f_1 => zgui.Key.f1,
            .f_2 => zgui.Key.f2,
            .f_3 => zgui.Key.f3,
            .f_4 => zgui.Key.f4,
            .f_5 => zgui.Key.f5,
            .f_6 => zgui.Key.f6,
            .f_7 => zgui.Key.f7,
            .f_8 => zgui.Key.f8,
            .f_9 => zgui.Key.f9,
            .f_10 => zgui.Key.f10,
            .f_11 => zgui.Key.f11,
            .f_12 => zgui.Key.f12,
            .kp_0 => zgui.Key.keypad_0,
            .kp_1 => zgui.Key.keypad_1,
            .kp_2 => zgui.Key.keypad_2,
            .kp_3 => zgui.Key.keypad_3,
            .kp_4 => zgui.Key.keypad_4,
            .kp_5 => zgui.Key.keypad_5,
            .kp_6 => zgui.Key.keypad_6,
            .kp_7 => zgui.Key.keypad_7,
            .kp_8 => zgui.Key.keypad_8,
            .kp_9 => zgui.Key.keypad_9,
            .kp_decimal => zgui.Key.keypad_decimal,
            .kp_divide => zgui.Key.keypad_divide,
            .kp_multiply => zgui.Key.keypad_multiply,
            .kp_subtract => zgui.Key.keypad_subtract,
            .kp_add => zgui.Key.keypad_add,
            .kp_enter => zgui.Key.keypad_enter,
            .kp_equal => zgui.Key.keypad_equal,
            .left_shift => zgui.Key.left_shift,
            .left_control => zgui.Key.left_ctrl,
            .left_alt => zgui.Key.left_alt,
            .left_super => zgui.Key.left_super,
            .right_shift => zgui.Key.right_shift,
            .right_control => zgui.Key.right_ctrl,
            .right_alt => zgui.Key.right_alt,
            .right_super => zgui.Key.right_super,
            .menu => zgui.Key.menu,

            .mouse_1 => zgui.Key.mouse_left,
            .mouse_2 => zgui.Key.mouse_right,
            .mouse_3 => zgui.Key.mouse_middle,

            else => return null,
        };
    }
};
