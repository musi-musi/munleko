const std = @import("std");
const zgui = @import("zgui");

const Allocator = std.mem.Allocator;

const Window = @import("window").Window;

extern fn imgui_backend_init(win: Window.Handle) void;
extern fn imgui_backend_deinit() void;
extern fn imgui_backend_newframe() void;
extern fn imgui_backend_render() void;

pub fn init(allocator: Allocator, window: Window) void {
    zgui.init(allocator);
    imgui_backend_init(window.handle);
    zgui.io.setIniFilename(null);
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
