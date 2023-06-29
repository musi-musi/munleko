const std = @import("std");
const zgui = @import("zgui");

const Allocator = std.mem.Allocator;

const font_ttf = @embedFile("gui/Rubik-Medium.ttf");

const Window = @import("window").Window;

extern fn imgui_backend_init(win: Window.Handle) void;
extern fn imgui_backend_deinit() void;
extern fn imgui_backend_newframe() void;
extern fn imgui_backend_render() void;

pub fn init(allocator: Allocator, window: Window) void {
    zgui.init(allocator);
    zgui.io.setIniFilename(null);
    const font = zgui.io.addFontFromMemory(font_ttf, 36);
    _ = font;
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
}

pub fn deinit() void {
    zgui.deinit();
}

pub fn newFrame() void {
    imgui_backend_newframe();
    zgui.newFrame();
}

pub fn render() void {
    zgui.render();
    imgui_backend_render();
}

pub fn showFrameRate(fps: f32) void {
    zgui.setNextWindowPos(.{ .x = 8, .y = 8 });
    _ = zgui.begin("fps", .{
        .flags = .{
            .no_title_bar = true,
            .no_move = true,
            .no_resize = true,
            .always_auto_resize = true,
        },
    });
    defer zgui.end();
    zgui.text("fps: {d: >5}", .{fps});
}
