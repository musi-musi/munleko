const std = @import("std");
const zgui = @import("zgui");

const Allocator = std.mem.Allocator;

const font_ttf = @embedFile("gui/Rubik-Medium.ttf");

const Window = @import("window").Window;

const Gui = @This();

extern fn imgui_backend_init(win: Window.Handle) void;
extern fn imgui_backend_deinit() void;
extern fn imgui_backend_newframe() void;
extern fn imgui_backend_render() void;

allocator: Allocator,
fonts: Fonts,

pub const Fonts = struct {
    normal: zgui.Font,
    large: zgui.Font,
};

pub fn init(allocator: Allocator, window: Window) Gui {
    zgui.init(allocator);
    zgui.io.setIniFilename(null);
    const fonts = Fonts{
        .normal = zgui.io.addFontFromMemory(font_ttf, 36),
        .large = zgui.io.addFontFromMemory(font_ttf, 80),
    };

    zgui.io.setDefaultFont(fonts.normal);

    const style = zgui.getStyle();
    style.window_border_size = 0;
    style.tab_border_size = 0;
    style.child_border_size = 0;
    style.frame_border_size = 0;
    style.popup_border_size = 0;
    style.separator_text_border_size = 0;
    const rounding = 8;
    style.tab_rounding = rounding;
    style.grab_rounding = rounding;
    style.child_rounding = rounding;
    style.frame_rounding = rounding;
    style.popup_rounding = rounding;
    style.window_rounding = rounding;
    style.scrollbar_rounding = rounding;

    style.anti_aliased_lines_use_tex = false;

    imgui_backend_init(window.handle);

    return .{
        .allocator = allocator,
        .fonts = fonts,
    };
}

pub fn deinit(self: *Gui) void {
    _ = self;
    zgui.deinit();
}

pub fn newFrame(self: *Gui) void {
    _ = self;
    imgui_backend_newframe();
    zgui.newFrame();
}

pub fn render(self: *Gui) void {
    _ = self;
    zgui.render();
    imgui_backend_render();
}

pub fn showStats(self: *Gui, fps: f32) void {
    _ = self;
    zgui.setNextWindowPos(.{ .x = 8, .y = 8 });
    _ = zgui.begin("fps", .{
        .flags = .{
            .no_title_bar = true,
            .no_move = true,
            .no_resize = true,
        },
    });
    defer zgui.end();
    zgui.pushItemWidth(128);
    defer zgui.popItemWidth();
    zgui.labelText("fps", "{d}", .{fps});
}

pub fn showHud(self: *Gui) void {
    const screen_size = zgui.io.getDisplaySize();
    zgui.setNextWindowPos(.{
        .x = 32,
        .y = screen_size[1] - 32,
        .pivot_x = 0,
        .pivot_y = 1,
    });
    _ = zgui.begin("health", .{
        .flags = .{
            .no_title_bar = true,
            .no_move = true,
            .no_resize = true,
        },
    });
    defer zgui.end();
    zgui.pushFont(self.fonts.large);
    defer zgui.popFont();
    zgui.text("100", .{});

    const fg_draw = zgui.getForegroundDrawList();
    fg_draw.addCircleFilled(.{
        .p = .{ screen_size[0] / 2, screen_size[1] / 2 },
        .r = 4,
        .col = 0xffffffff,
    });
}
