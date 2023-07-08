const std = @import("std");
const zgui = @import("zgui");
const nm = @import("nm");

const Vec2 = nm.Vec2;
const vec2 = nm.vec2;

const Allocator = std.mem.Allocator;

const font_ttf = @embedFile("gui/Rubik-Medium.ttf");

const Window = @import("window").Window;

const Gui = @This();

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

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

pub fn init(allocator: Allocator, window: *Window) !Gui {
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

pub const Radial = struct {
    /// if null, show in center of screen
    position: ?Vec2 = null,
    radius_inner: f32,
    radius_outer: f32,
    radius_deadzone: f32,
};

pub const RadialWedge = struct {
    radial_center: Vec2,
    is_hovered: bool,
    center: Vec2,
};

pub fn showRadial(self: *Gui, radial: Radial, wedges: []RadialWedge, mouse_position: Vec2) void {
    const position = radial.position orelse vec2(zgui.io.getDisplaySize()).divScalar(2);
    const delta_theta = std.math.pi * 2 / @as(f32, @floatFromInt(wedges.len));
    const draw_list = zgui.getForegroundDrawList();
    const relative_mouse_position = mouse_position.sub(position);
    const in_deadzone = relative_mouse_position.mag() < radial.radius_deadzone;
    var mouse_theta = std.math.atan2(f32, relative_mouse_position.v[1], relative_mouse_position.v[0]);
    const mouse_wedge_index_signed: i32 = @intFromFloat((@floor((mouse_theta / delta_theta) + 0.5)));
    const mouse_wedge_index: usize = @intCast(@mod(mouse_wedge_index_signed, @as(i32, @intCast(wedges.len))));
    const radius_center = (radial.radius_outer + radial.radius_inner) / 2;
    draw_list.addCircle(.{
        .p = position.v,
        .r = radius_center,
        .col = zgui.colorConvertFloat4ToU32(zgui.getStyle().getColor(.window_bg)),
        .thickness = radial.radius_outer - radial.radius_inner,
    });
    for (wedges, 0..) |*wedge, w| {
        wedge.radial_center = position;
        const w_f32: f32 = @floatFromInt(w);
        const theta_start = (w_f32 - 0.5) * delta_theta;
        const theta_end = (w_f32 + 0.5) * delta_theta;
        const theta = w_f32 * delta_theta;
        wedge.is_hovered = (!in_deadzone) and w == mouse_wedge_index;
        wedge.center = position.add(angleToVector(theta, radius_center));
        if (wedge.is_hovered) {
            const thickness = 8;
            draw_list.pathArcTo(.{
                .p = position.v,
                .r = radial.radius_inner + thickness,
                .amin = theta_start,
                .amax = theta_end,
            });
            draw_list.pathStroke(.{
                .col = zgui.colorConvertFloat4ToU32(.{ 1, 1, 1, 1 }),
                .flags = zgui.DrawFlags.round_corners_all,
                .thickness = thickness,
            });
        }
    }

    _ = self;
}

fn angleToVector(theta: f32, len: f32) Vec2 {
    return vec2(.{
        @cos(theta) * len,
        @sin(theta) * len,
    });
}

const LekoType = Engine.leko.LekoType;
const LekoValue = Engine.leko.LekoValue;

pub fn showEquipSelectRadial(self: *Gui, mouse_position: Vec2, comptime count: usize, values: *const [count]?LekoType) ?LekoType {
    var wedges: [count]RadialWedge = undefined;
    self.showRadial(.{
        .radius_inner = 128,
        .radius_outer = 256,
        .radius_deadzone = 64,
    }, &wedges, mouse_position);
    var selection: ?LekoType = null;
    const draw_list = zgui.getForegroundDrawList();
    const font = self.fonts.normal;
    zgui.pushFont(font);
    defer zgui.popFont();
    for (wedges, 0..) |wedge, w| {
        if (wedge.is_hovered) {
            selection = values.*[w];
        }
        if (values.*[w]) |leko_type| {
            const text = leko_type.name;
            const size = vec2(zgui.calcTextSize(text, .{}));
            draw_list.addTextUnformatted(wedge.center.sub(size.divScalar(2)).v, 0xffffffff, text);
        }
    }
    return selection;
}
