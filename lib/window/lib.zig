const std = @import("std");
const util = @import("util");

const builtin = @import("builtin");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("glfw3.h");
});

const Allocator = std.mem.Allocator;

pub const Handle = ?*c.GLFWwindow;

pub fn init() !void {
    if (c.glfwInit() == 0) {
        return error.GlfwInitFailed;
    }
}

pub fn deinit() void {
    c.glfwTerminate();
}

pub const GlContextOptions = struct {
    version_major: c_int = 3,
    version_minor: c_int = 3,
    profile: Profile = .core,

    pub const Profile = enum(c_int) {
        core = c.GLFW_OPENGL_CORE_PROFILE,
        compat = c.GLFW_OPENGL_COMPAT_PROFILE,
        any = c.GLFW_OPENGL_ANY_PROFILE,
    };
};

pub const getGlProcAddress = &c.glfwGetProcAddress;

pub const Vsync = enum(c_int) {
    disabled = 0,
    enabled = 1,
};

pub const Window = struct {
    allocator: Allocator,
    handle: Handle = null,
    events: Events,
    held_buttons: ButtonSet = .{},
    size: [2]u32 = .{ 1280, 720 },
    vsync: Vsync = .disabled,
    mouse_mode: MouseMode = .visible,

    pub const Events = util.Events(union(enum) {
        button_pressed: ButtonCode,
        button_released: ButtonCode,
        framebuffer_size: [2]u32,
    });

    pub const ButtonSet = std.AutoHashMapUnmanaged(ButtonCode, void);

    pub fn init(allocator: Allocator) Window {
        return .{
            .allocator = allocator,
            .events = Events.init(allocator),
        };
    }

    pub fn deinit(self: *Window) void {
        if (self.handle != null) {
            self.destroy();
        }
        self.events.deinit();
        self.held_buttons.deinit(self.allocator);
    }

    fn fromUserPtr(handle: Handle) *Window {
        return @ptrCast(*Window, @alignCast(@alignOf(Window), c.glfwGetWindowUserPointer(handle).?));
    }

    pub fn create(self: *Window, gl_options: GlContextOptions) !void {
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, @intCast(c_int, gl_options.version_major));
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, @intCast(c_int, gl_options.version_minor));
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, @intFromEnum(gl_options.profile));
        c.glfwWindowHint(c.GLFW_SAMPLES, 8);
        const debug: c_int = (if (builtin.mode == .Debug) c.GLFW_TRUE else c.GLFW_FALSE);
        c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, debug);

        if (c.glfwCreateWindow(@intCast(c_int, self.size[0]), @intCast(c_int, self.size[1]), "window", null, null)) |handle| {
            self.handle = handle;
            c.glfwSetWindowUserPointer(handle, self);
            _ = c.glfwSetKeyCallback(handle, keyCallback);
            _ = c.glfwSetMouseButtonCallback(handle, mouseButtonCallback);
            _ = c.glfwSetFramebufferSizeCallback(self.handle, framebufferSizeCallback);
        } else {
            return error.GlfwCreateWindowFailed;
        }

        self.setVsync(self.vsync);
    }

    pub fn destroy(self: *Window) void {
        c.glfwDestroyWindow(self.handle);
        self.handle = null;
    }

    pub fn makeContextCurrent(self: Window) void {
        c.glfwMakeContextCurrent(self.handle);
    }

    pub fn setVsync(self: *Window, vsync: Vsync) void {
        self.vsync = vsync;
        c.glfwSwapInterval(@intFromEnum(vsync));
    }

    pub fn nextFrame(self: *Window) bool {
        self.events.clearAll();
        c.glfwSwapBuffers(self.handle);
        c.glfwPollEvents();
        return c.glfwWindowShouldClose(self.handle) == 0;
    }

    pub fn setShouldClose(self: Window) void {
        c.glfwSetWindowShouldClose(self.handle, c.GLFW_TRUE);
    }

    fn keyCallback(handle: Handle, key: c_int, _: c_int, action: c_int, _: c_int) callconv(.C) void {
        const self = fromUserPtr(handle);
        const code = @enumFromInt(ButtonCode, key);
        self.buttonCallback(code, action) catch |err| {
            @panic(@errorName(err));
        };
    }

    fn mouseButtonCallback(handle: Handle, button: c_int, action: c_int, _: c_int) callconv(.C) void {
        const self = fromUserPtr(handle);
        const code = @enumFromInt(ButtonCode, button + c.GLFW_KEY_LAST + 1);
        self.buttonCallback(code, action) catch |err| {
            @panic(@errorName(err));
        };
    }

    fn framebufferSizeCallback(handle: Handle, width: c_int, height: c_int) callconv(.C) void {
        const self = fromUserPtr(handle);
        self.size = .{
            @intCast(u32, width),
            @intCast(u32, height),
        };
        self.events.post(.framebuffer_size, self.size) catch |err| {
            @panic(@errorName(err));
        };
    }

    fn buttonCallback(self: *Window, button: ButtonCode, action: c_int) !void {
        switch (action) {
            c.GLFW_PRESS => {
                try self.events.post(.button_pressed, button);
                try self.held_buttons.put(self.allocator, button, {});
            },
            c.GLFW_RELEASE => {
                try self.events.post(.button_released, button);
                _ = self.held_buttons.remove(button);
            },
            else => {},
        }
    }

    pub fn buttonPressed(self: Window, button: ButtonCode) bool {
        for (self.events.get(.button_pressed)) |code| {
            if (code == button) {
                return true;
            }
        }
        return false;
    }

    pub fn buttonReleased(self: Window, button: ButtonCode) bool {
        for (self.events.get(.button_released)) |code| {
            if (code == button) {
                return true;
            }
        }
        return false;
    }

    pub fn buttonHeld(self: Window, button: ButtonCode) bool {
        return self.held_buttons.contains(button);
    }

    pub fn mousePosition(self: Window) [2]f32 {
        var x: f64 = undefined;
        var y: f64 = undefined;
        c.glfwGetCursorPos(self.handle, &x, &y);
        return [2]f32{
            @floatCast(f32, x),
            @floatCast(f32, y),
        };
    }

    pub fn setMousePosition(self: Window, pos: [2]f32) void {
        c.glfwSetCursorPos(self.handle, @floatCast(f64, pos[0]), @floatCast(f64, pos[1]));
    }

    pub fn setMouseMode(self: *Window, mode: MouseMode) void {
        c.glfwSetInputMode(self.handle, c.GLFW_CURSOR, @intFromEnum(mode));
        self.mouse_mode = mode;
        if (self.isRawMouseSupported()) {
            switch (mode) {
                .disabled => c.glfwSetInputMode(self.handle, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE),
                else => c.glfwSetInputMode(self.handle, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_FALSE),
            }
        }
        c.glfwPollEvents();
    }

    pub fn isRawMouseSupported(_: Window) bool {
        return c.glfwRawMouseMotionSupported() != c.GLFW_FALSE;
    }
};

pub const ButtonEvent = enum {
    pressed,
    released,
};

pub const ButtonState = enum(c_int) {
    down = c.GLFW_PRESS,
    up = c.GLFW_RELEASE,
};

pub const ButtonCode = enum(c_int) {
    const Self = @This();

    fn fromButtonCode(key: ButtonCode) Self {
        return std.enums.values(Self)[@intFromEnum(key)];
    }

    fn keyType(self: Self) ButtonType {
        const mouse_start = @intFromEnum(Self.mouse_1);
        if (@intFromEnum(self) >= mouse_start) {
            return .mouse;
        } else {
            return .keyboard;
        }
    }

    fn glfwCode(self: Self) c_int {
        switch (self.keyType()) {
            .keyboard => return @intFromEnum(self),
            .mouse => return @intFromEnum(self) - (c.GLFW_KEY_LAST + 1),
        }
    }

    const ButtonType = enum {
        keyboard,
        mouse,
    };

    space = c.GLFW_KEY_SPACE,
    apostrophe = c.GLFW_KEY_APOSTROPHE,
    comma = c.GLFW_KEY_COMMA,
    minus = c.GLFW_KEY_MINUS,
    period = c.GLFW_KEY_PERIOD,
    slash = c.GLFW_KEY_SLASH,
    alpha_0 = c.GLFW_KEY_0,
    alpha_1 = c.GLFW_KEY_1,
    alpha_2 = c.GLFW_KEY_2,
    alpha_3 = c.GLFW_KEY_3,
    alpha_4 = c.GLFW_KEY_4,
    alpha_5 = c.GLFW_KEY_5,
    alpha_6 = c.GLFW_KEY_6,
    alpha_7 = c.GLFW_KEY_7,
    alpha_8 = c.GLFW_KEY_8,
    alpha_9 = c.GLFW_KEY_9,
    semicolon = c.GLFW_KEY_SEMICOLON,
    equal = c.GLFW_KEY_EQUAL,
    a = c.GLFW_KEY_A,
    b = c.GLFW_KEY_B,
    c = c.GLFW_KEY_C,
    d = c.GLFW_KEY_D,
    e = c.GLFW_KEY_E,
    f = c.GLFW_KEY_F,
    g = c.GLFW_KEY_G,
    h = c.GLFW_KEY_H,
    i = c.GLFW_KEY_I,
    j = c.GLFW_KEY_J,
    k = c.GLFW_KEY_K,
    l = c.GLFW_KEY_L,
    m = c.GLFW_KEY_M,
    n = c.GLFW_KEY_N,
    o = c.GLFW_KEY_O,
    p = c.GLFW_KEY_P,
    q = c.GLFW_KEY_Q,
    r = c.GLFW_KEY_R,
    s = c.GLFW_KEY_S,
    t = c.GLFW_KEY_T,
    u = c.GLFW_KEY_U,
    v = c.GLFW_KEY_V,
    w = c.GLFW_KEY_W,
    x = c.GLFW_KEY_X,
    y = c.GLFW_KEY_Y,
    z = c.GLFW_KEY_Z,
    left_bracket = c.GLFW_KEY_LEFT_BRACKET,
    backslash = c.GLFW_KEY_BACKSLASH,
    right_bracket = c.GLFW_KEY_RIGHT_BRACKET,
    grave = c.GLFW_KEY_GRAVE_ACCENT,
    world_1 = c.GLFW_KEY_WORLD_1,
    world_2 = c.GLFW_KEY_WORLD_2,
    escape = c.GLFW_KEY_ESCAPE,
    enter = c.GLFW_KEY_ENTER,
    tab = c.GLFW_KEY_TAB,
    backspace = c.GLFW_KEY_BACKSPACE,
    insert = c.GLFW_KEY_INSERT,
    delete = c.GLFW_KEY_DELETE,
    right = c.GLFW_KEY_RIGHT,
    left = c.GLFW_KEY_LEFT,
    down = c.GLFW_KEY_DOWN,
    up = c.GLFW_KEY_UP,
    page_up = c.GLFW_KEY_PAGE_UP,
    page_down = c.GLFW_KEY_PAGE_DOWN,
    home = c.GLFW_KEY_HOME,
    end = c.GLFW_KEY_END,
    caps_lock = c.GLFW_KEY_CAPS_LOCK,
    scroll_lock = c.GLFW_KEY_SCROLL_LOCK,
    num_lock = c.GLFW_KEY_NUM_LOCK,
    print_screen = c.GLFW_KEY_PRINT_SCREEN,
    pause = c.GLFW_KEY_PAUSE,
    f_1 = c.GLFW_KEY_F1,
    f_2 = c.GLFW_KEY_F2,
    f_3 = c.GLFW_KEY_F3,
    f_4 = c.GLFW_KEY_F4,
    f_5 = c.GLFW_KEY_F5,
    f_6 = c.GLFW_KEY_F6,
    f_7 = c.GLFW_KEY_F7,
    f_8 = c.GLFW_KEY_F8,
    f_9 = c.GLFW_KEY_F9,
    f_10 = c.GLFW_KEY_F10,
    f_11 = c.GLFW_KEY_F11,
    f_12 = c.GLFW_KEY_F12,
    f_13 = c.GLFW_KEY_F13,
    f_14 = c.GLFW_KEY_F14,
    f_15 = c.GLFW_KEY_F15,
    f_16 = c.GLFW_KEY_F16,
    f_17 = c.GLFW_KEY_F17,
    f_18 = c.GLFW_KEY_F18,
    f_19 = c.GLFW_KEY_F19,
    f_20 = c.GLFW_KEY_F20,
    f_21 = c.GLFW_KEY_F21,
    f_22 = c.GLFW_KEY_F22,
    f_23 = c.GLFW_KEY_F23,
    f_24 = c.GLFW_KEY_F24,
    f_25 = c.GLFW_KEY_F25,
    kp_0 = c.GLFW_KEY_KP_0,
    kp_1 = c.GLFW_KEY_KP_1,
    kp_2 = c.GLFW_KEY_KP_2,
    kp_3 = c.GLFW_KEY_KP_3,
    kp_4 = c.GLFW_KEY_KP_4,
    kp_5 = c.GLFW_KEY_KP_5,
    kp_6 = c.GLFW_KEY_KP_6,
    kp_7 = c.GLFW_KEY_KP_7,
    kp_8 = c.GLFW_KEY_KP_8,
    kp_9 = c.GLFW_KEY_KP_9,
    kp_decimal = c.GLFW_KEY_KP_DECIMAL,
    kp_divide = c.GLFW_KEY_KP_DIVIDE,
    kp_multiply = c.GLFW_KEY_KP_MULTIPLY,
    kp_subtract = c.GLFW_KEY_KP_SUBTRACT,
    kp_add = c.GLFW_KEY_KP_ADD,
    kp_enter = c.GLFW_KEY_KP_ENTER,
    kp_equal = c.GLFW_KEY_KP_EQUAL,
    left_shift = c.GLFW_KEY_LEFT_SHIFT,
    left_control = c.GLFW_KEY_LEFT_CONTROL,
    left_alt = c.GLFW_KEY_LEFT_ALT,
    left_super = c.GLFW_KEY_LEFT_SUPER,
    right_shift = c.GLFW_KEY_RIGHT_SHIFT,
    right_control = c.GLFW_KEY_RIGHT_CONTROL,
    right_alt = c.GLFW_KEY_RIGHT_ALT,
    right_super = c.GLFW_KEY_RIGHT_SUPER,
    menu = c.GLFW_KEY_MENU,
    unknown = c.GLFW_KEY_UNKNOWN,

    mouse_1 = c.GLFW_MOUSE_BUTTON_1 + c.GLFW_KEY_LAST + 1,
    mouse_2 = c.GLFW_MOUSE_BUTTON_2 + c.GLFW_KEY_LAST + 1,
    mouse_3 = c.GLFW_MOUSE_BUTTON_3 + c.GLFW_KEY_LAST + 1,
    mouse_4 = c.GLFW_MOUSE_BUTTON_4 + c.GLFW_KEY_LAST + 1,
    mouse_5 = c.GLFW_MOUSE_BUTTON_5 + c.GLFW_KEY_LAST + 1,
    mouse_6 = c.GLFW_MOUSE_BUTTON_6 + c.GLFW_KEY_LAST + 1,
    mouse_7 = c.GLFW_MOUSE_BUTTON_7 + c.GLFW_KEY_LAST + 1,
    mouse_8 = c.GLFW_MOUSE_BUTTON_8 + c.GLFW_KEY_LAST + 1,
};

pub const MouseMode = enum(c_int) {
    visible = c.GLFW_CURSOR_NORMAL,
    hidden = c.GLFW_CURSOR_HIDDEN,
    disabled = c.GLFW_CURSOR_DISABLED,
};
