const std = @import("std");
const window = @import("window");
const gl = @import("gl");
const ls = @import("ls");
const nm = @import("nm");
const util = @import("util");
const zlua = @import("ziglua");
const oko = @import("oko");

const Allocator = std.mem.Allocator;

const Client = @This();

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;

const Engine = @import("Engine.zig");
const Session = Engine.Session;
const World = Engine.World;

const Mutex = std.Thread.Mutex;

const Window = window.Window;

pub const rendering = @import("rendering.zig");
const SessionRenderer = rendering.SessionRenderer;
const Scene = rendering.Scene;
const Camera = Scene.Camera;

pub const main_decls = struct {
    pub const std_options = struct {
        pub const log_level = std.log.Level.info;
    };

    pub fn main() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        // try oko.start();
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

const FlyCam = @import("client/FlyCam.zig");

allocator: Allocator,
window: Window,
engine: *Engine,
observer: World.Observer = undefined,

pub fn init(self: *Client, allocator: Allocator) !void {
    const args = try Engine.Arguments.initFromCommandLineArgs();
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

    try gl.init(window.getGlProcAddress);
    gl.viewport(self.window.size);
    gl.enable(.depth_test);
    gl.setDepthFunction(.less);
    gl.enable(.cull_face);

    var session = try self.engine.createSession();
    defer session.destroy();

    try session.applyAssets(self.engine.assets);

    var camera = Camera{};
    const session_renderer = try SessionRenderer.create(allocator, session, &camera);
    defer session_renderer.destroy();

    try session_renderer.applyAssets(self.engine.assets);

    var fly_cam = FlyCam.init(self.window);
    fly_cam.move_speed = 32;

    const cam_obs = try session.world.observers.create(fly_cam.position.cast(i32));
    defer session.world.observers.delete(cam_obs);
    self.observer = cam_obs;

    try session_renderer.start(cam_obs);
    defer session_renderer.stop();

    try session.start(SessionContext{
        .client = self,
        .session_renderer = session_renderer,
    }, .{
        .on_tick = SessionContext.onTick,
        .on_world_update = SessionContext.onWorldUpdate,
    });
    defer session.stop();

    self.window.setMouseMode(.disabled);

    gl.clearDepth(.float, 1);

    var fps_counter = try util.FpsCounter.start(1);

    session_renderer.scene.directional_light = nm.vec3(.{ 1, 3, 2 }).norm() orelse unreachable;

    while (self.window.nextFrame()) {
        oko.tick();
        for (self.window.events.get(.framebuffer_size)) |size| {
            gl.viewport(size);
        }
        if (self.window.buttonPressed(.grave)) {
            switch (self.window.mouse_mode) {
                .disabled => self.window.setMouseMode(.visible),
                else => self.window.setMouseMode(.disabled),
            }
        }
        if (self.window.buttonPressed(.f_10)) {
            self.window.setVsync(switch (self.window.vsync) {
                .enabled => .disabled,
                .disabled => .enabled,
            });
        }

        fly_cam.update(self.window);
        session.world.observers.setPosition(cam_obs, fly_cam.position.cast(i32));

        camera.setViewMatrix(fly_cam.viewMatrix());
        camera.setProjectionPerspective(.{
            .fov = 90,
            .aspect_ratio = @intToFloat(f32, self.window.size[0]) / @intToFloat(f32, self.window.size[1]),
            .near_plane = 0.001,
            .far_plane = 1000,
        });

        // session_renderer.scene.camera_view = fly_cam.viewMatrix();
        // session_renderer.scene.camera_projection = (
        //     nm.transform.createPerspective(
        //         90.0 * std.math.pi / 180.0,
        //         @intToFloat(f32, self.window.size[0]) / @intToFloat(f32, self.window.size[1]),
        //         0.001,
        //         1000,
        //     )
        // );

        gl.clearColor(session_renderer.scene.fog_color.addDimension(1).v);
        gl.clear(.color_depth);

        try session_renderer.update();
        session_renderer.draw();

        if (fps_counter.frame()) |frames| {
            // _ = frames;
            std.log.info("fps: {d}", .{frames});
        }
    }
}

const SessionContext = struct {
    client: *Client,
    session_renderer: *SessionRenderer,

    fn onTick(self: SessionContext, session: *Session) !void {
        _ = self;
        _ = session;
    }

    fn onWorldUpdate(self: SessionContext, world: *World) !void {
        // _ = self;
        // _ = world;
        try self.session_renderer.onWorldUpdate(world);
    }
};
