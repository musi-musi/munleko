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

pub const rendering = @import("client/rendering.zig");
const SessionRenderer = rendering.SessionRenderer;
const Scene = rendering.Scene;
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

        var client: Client = undefined;
        try client.init(allocator);
        defer client.deinit();

        try client.run();

        // try oko.dumpAllocHistoryCsvFile("oko.csv");
    }
};

allocator: Allocator,
window: Window,
engine: *Engine,

pub fn init(self: *Client, allocator: Allocator) !void {
    const args = try Engine.Arguments.initFromCommandLineArgs(allocator);
    defer args.deinit(allocator);
    self.* = .{
        .allocator = allocator,
        .window = Window.init(allocator),
        .engine = try Engine.create(allocator, args),
    };
}

pub fn deinit(self: *Client) void {
    self.window.deinit();
    self.engine.destroy();
}

pub fn run(self: *Client) !void {
    const allocator = self.allocator;

    try self.engine.load();

    try self.window.create(.{});
    defer self.window.destroy();
    self.window.makeContextCurrent();
    self.window.setVsync(.disabled);
    // self.window.setDisplayMode(.borderless);

    try gl.init(window.getGlProcAddress);
    gl.viewport(self.window.size);
    gl.enable(.depth_test);
    gl.setDepthFunction(.less);
    gl.enable(.cull_face);

    var gui = Gui.init(self.allocator, self.window);
    defer gui.deinit();

    var session = try self.engine.createSession();
    defer session.destroy();

    try session.applyAssets(self.engine.assets);

    var camera = Camera{};
    const session_renderer = try SessionRenderer.create(allocator, session, &camera);
    defer session_renderer.destroy();

    try session_renderer.applyAssets(self.engine.assets);

    var player = try Player.init(session.world, Vec3.zero);
    defer player.deinit();

    player.leko_equip = session.world.leko_data.leko_types.getForName("brick");

    var prev_player_eye = player.eyePosition();

    var input = Input.init(&self.window, &player);
    defer input.deinit();

    try session_renderer.start(player.observer);
    defer session_renderer.stop();

    const player_renderer = try rendering.PlayerRenderer.create(allocator, &session_renderer.scene, &player);
    defer player_renderer.destroy();

    var session_context = SessionContext{
        .client = self,
        .session_renderer = session_renderer,
    };

    try session.start(&session_context, .{
        // .on_tick = SessionContext.onTick,
        .on_world_update = SessionContext.onWorldUpdate,
    });
    defer session.stop();

    self.window.setMouseMode(.disabled);

    gl.clearDepth(.float, 1);

    var fps_counter = try util.FpsCounter.start(0.25);
    var frame_time = try util.FrameTime.start();

    session_renderer.scene.directional_light = nm.vec3(.{ 1, 3, 2 }).norm() orelse unreachable;

    while (self.window.nextFrame()) {
        frame_time.frame();
        gui.newFrame();
        gl.viewport(self.window.size);
        if (self.window.buttonPressed(.grave)) {
            switch (input.state) {
                .gameplay => input.setState(.menu),
                .menu => input.setState(.gameplay),
            }
        }
        if (self.window.buttonPressed(.f_10)) {
            self.window.setVsync(switch (self.window.vsync) {
                .enabled => .disabled,
                .disabled => .enabled,
            });
        }
        if (self.window.buttonPressed(.f_4)) {
            self.window.setDisplayMode(util.cycleEnum(self.window.display_mode));
        }

        input.frame();

        if ((try session.frameTicks()) > 0) {
            prev_player_eye = player.eyePosition();
            try player.onTick(session);
        }

        const interpolated_player_position = prev_player_eye.lerpTo(player.eyePosition(), session.tickProgress());

        camera.setViewMatrix(nm.transform.createTranslate(interpolated_player_position.neg()).mul(player.lookMatrix()));
        camera.setProjectionPerspective(.{
            .fov = 90,
            .aspect_ratio = @as(f32, @floatFromInt(self.window.size[0])) / @as(f32, @floatFromInt(self.window.size[1])),
            .near_plane = 0.01,
            .far_plane = 1000,
        });

        gl.clearColor(session_renderer.scene.fog_color.addDimension(1).v);
        gl.clear(.color_depth);

        try session_renderer.update();
        session_renderer.draw();

        player_renderer.draw();

        _ = fps_counter.frame();

        // zgui.showDemoWindow(null);
        gui.showStats(fps_counter.fps);
        gui.showHud();
        gui.render();
    }
}

const SessionContext = struct {
    client: *Client,
    session_renderer: *SessionRenderer,

    fn onTick(self: *SessionContext, session: *Session) !void {
        self.prev_player_eye = self.player.position;
        self.player.onTick(session);
    }

    fn onWorldUpdate(self: *SessionContext, world: *World) !void {
        // _ = self;
        // _ = world;
        try self.session_renderer.onWorldUpdate(world);
    }
};
