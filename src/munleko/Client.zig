const std = @import("std");
const window = @import("window");
const gl = @import("gl");
const ls = @import("ls");
const nm = @import("nm");
const util = @import("util");
const zlua = @import("ziglua");
const oko = @import("oko");
const zgui = @import("zgui");

const Allocator = std.mem.Allocator;

const Client = @This();

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;

const Engine = @import("Engine.zig");
const Session = Engine.Session;
const World = Engine.World;
const Player = Engine.Player;

const Mutex = std.Thread.Mutex;

const Window = window.Window;

pub const Renderer = @import("client/Renderer.zig");
const SessionRenderer = Renderer.SessionRenderer;
const Scene = Renderer.Scene;
const Camera = Scene.Camera;

pub const Gui = @import("client/Gui.zig");
pub const Input = @import("client/Input.zig");

pub const main_decls = struct {
    pub const std_options = struct {
        pub const log_level = std.log.Level.info;
    };

    pub fn main() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        // try oko.start(1.0 / 15.0);
        // defer oko.stop();

        // const allocator = oko.wrapAllocator("gpa", gpa.allocator());
        const allocator = gpa.allocator();

        try window.init();
        defer window.deinit();

        const client = try Client.create(allocator);
        defer client.destroy();

        try client.run();

        // try oko.dumpAllocHistoryCsvFile("oko.csv");
    }
};

allocator: Allocator,
window: *Window,

input: Input,
engine: *Engine,
renderer: *Renderer,
gui: Gui,

session_state: ?SessionState = null,

pub const SessionState = struct {
    session: *Session,
    renderer: *SessionRenderer,
};

pub fn create(allocator: Allocator) !*Client {
    const self = try allocator.create(Client);
    errdefer allocator.destroy(self);

    const args = try Engine.Arguments.initFromCommandLineArgs(allocator);
    defer args.deinit(allocator);
    const engine = try Engine.create(allocator, args);
    errdefer engine.destroy();

    const win = try Window.create(allocator, .{});
    errdefer win.destroy();
    win.makeContextCurrent();
    try gl.init(window.getGlProcAddress);

    const renderer = try Renderer.create(allocator, engine);
    errdefer renderer.destroy();

    const gui = try Gui.init(allocator, win);
    errdefer gui.deinit();

    self.* = .{
        .allocator = allocator,
        .window = win,
        .input = Input.init(self),
        .engine = engine,
        .renderer = renderer,
        .gui = gui,
    };

    return self;
}

pub fn destroy(self: *Client) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    if (self.session_state) |state| {
        state.renderer.stop();
        state.session.stop();
        state.renderer.destroy();
        state.session.destroy();
    }
    self.gui.deinit();
    self.window.destroy();
    self.engine.destroy();
    self.renderer.destroy();
    self.input.deinit();
}

fn startSession(self: *Client) !void {
    const session = try self.engine.createSession();
    errdefer session.destroy();
    const renderer = try self.renderer.createSessionRenderer(session);
    errdefer renderer.destroy();
    try renderer.start(session.player.observer);
    try session.start(self, .{
        .on_world_update = onWorldUpdate,
    });
    self.session_state = .{
        .session = session,
        .renderer = renderer,
    };
    self.input.setState(.gameplay);
}

fn stopSession(self: *Client) void {
    if (self.session_state) |state| {
        state.session.stop();
        state.renderer.stop();
        state.session.destroy();
        state.renderer.destroy();
    }
    self.session_state = null;
    self.input.setState(.menu);
}

pub fn run(self: *Client) !void {
    try self.engine.load();
    try self.renderer.applyAssets(self.engine.assets);

    self.window.makeContextCurrent();
    self.window.setVsync(.disabled);

    try self.startSession();
    defer self.stopSession();

    const session = self.session_state.?.session;
    const session_renderer = self.session_state.?.renderer;

    session.player.leko_equip = self.engine.assets.leko_type_table.getForName("brick");

    var fps_counter = try util.FpsCounter.start(0.25);
    var frame_time = try util.FrameTime.start();

    session_renderer.scene.directional_light = nm.vec3(.{ 1, 3, 2 }).norm() orelse unreachable;

    while (self.window.nextFrame()) {
        frame_time.frame();
        self.gui.newFrame();

        try self.update();

        gl.viewport(self.window.size);

        // zgui.showDemoWindow(null);
        _ = fps_counter.frame();
        self.gui.showStats(fps_counter.fps);
        if (self.session_state != null) {
            self.gui.showHud();
        }

        try self.draw();
    }
}

fn update(self: *Client) !void {
    self.input.update();
    if (self.session_state) |state| {
        const tick_count = state.session.tick_timer.countTicksAndReset();
        for (0..tick_count) |_| {
            try state.renderer.preTick();
            try state.session.tick();
        }
    }
}

fn draw(self: *Client) !void {
    if (self.session_state) |state| {
        const renderer = state.renderer;
        renderer.scene.camera.setScreenSize(self.window.size);
        renderer.scene.camera.setProjectionPerspective(.{
            .fov = 90,
            .near_plane = 0.01,
            .far_plane = 1000,
        });

        try renderer.update();
        renderer.draw();
    }
    self.gui.render();
}

fn onWorldUpdate(self: *Client, world: *World) !void {
    if (self.session_state) |state| {
        try state.renderer.onWorldUpdate(world);
    }
}
