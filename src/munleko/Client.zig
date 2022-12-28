const std = @import("std");
const window = @import("window");
const gl = @import("gl");
const ls = @import("ls");
const nm = @import("nm");
const util = @import("util");
const zlua = @import("ziglua");

const Allocator = std.mem.Allocator;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;


const Engine = @import("Engine.zig");
const Session = Engine.Session;
const World = Engine.World;

const Mutex = std.Thread.Mutex;

const Window = window.Window;

pub const rendering = @import("rendering.zig");


pub const main_decls = struct {

    pub const log_level = std.log.Level.info;

    pub fn main() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        const allocator = gpa.allocator();

        try window.init();
        defer window.deinit();

        var client: Client = undefined;
        try client.init(allocator);
        defer client.deinit();

        try client.run();
    }
};


const FlyCam = @import("client/FlyCam.zig");

const DrawChunk = struct {
    position: nm.Vec3i,
    state: World.ChunkLoadState,
};

const DrawMap = std.HashMapUnmanaged(World.Chunk, DrawChunk, World.Chunk.HashContext, std.hash_map.default_max_load_percentage);

pub const Client = struct {
    allocator: Allocator,
    window: Window,
    engine: Engine,
    draw_map: DrawMap = .{},
    draw_map_mutex: Mutex = .{},
    observer: World.Observer = undefined,

    pub fn init(self: *Client, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .window = Window.init(allocator),
            .engine = try Engine.init(allocator),
        };
    }

    pub fn deinit(self: *Client) void {
        self.window.deinit();
        self.engine.deinit();
        self.draw_map.deinit(self.allocator);
    }

    pub fn run(self: *Client) !void {
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

        var cam = FlyCam.init(self.window);
        cam.move_speed = 256;

        const cam_obs = try session.world.observers.create(cam.position.cast(i32));
        defer session.world.observers.delete(cam_obs) catch {};
        self.observer = cam_obs;

        try session.start(self, .{
            .on_tick = onTick,
            .on_world_update = onWorldUpdate,
        });

        self.window.setMouseMode(.disabled);

        const dbg = try rendering.Debug.init();
        defer dbg.deinit();

        dbg.setLight(vec3(.{ 1, 3, 2 }).norm() orelse unreachable);

        gl.clearColor(.{ 0, 0, 0, 1 });
        gl.clearDepth(.float, 1);

        dbg.start();

        var fps_counter = try util.FpsCounter.start(1);

        while (self.window.nextFrame()) {
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

            cam.update(self.window);
            session.world.observers.setPosition(cam_obs, cam.position.cast(i32));
            dbg.setView(cam.viewMatrix());

            gl.clear(.color_depth);
            dbg.setProj(nm.transform.createPerspective(
                90.0 * std.math.pi / 180.0,
                @intToFloat(f32, self.window.size[0]) / @intToFloat(f32, self.window.size[1]),
                0.001,
                1000,
            ));

            self.drawChunks(dbg);

            if (fps_counter.frame()) |frames| {
                _ = frames;
                // std.log.info("fps: {d}", .{frames});
            }
        }
    }

    fn onTick(self: *Client, session: *Session) !void {
        _ = self;
        _ = session;
        // if (session.tick_count % 100 == 0) {
        //     std.log.debug("tick {d}", .{ session.tick_count });
        // }
    }

    fn onWorldUpdate(self: *Client, world: *World) !void {
        const events = &world.observers.statuses.getPtr(self.observer).chunk_events;
        for (events.get(.enter)) |chunk| {
            try self.addDrawChunk(world, chunk);
        }
        for (events.get(.exit)) |chunk| {
            self.removeDrawChunk(chunk);
        }
        // const chunks = &world.chunks;
        // for (chunks.load_state_events.get(.loading)) |event| {
        //     try self.addDrawChunk(world, event.chunk);
        // }
        // for (chunks.load_state_events.get(.active)) |chunk| {
        //     try self.addDrawChunk(world, chunk);
        // }
        // for (chunks.load_state_events.get(.unloading)) |chunk| {
        //     try self.addDrawChunk(world, chunk);
        //     // self.removeDrawChunk(chunk);
        // }
        // for (chunks.load_state_events.get(.deleted)) |chunk| {
        //     self.removeDrawChunk(chunk);
        // }
        // std.time.sleep(0.5 * std.time.ns_per_s);
    }

    fn addDrawChunk(self: *Client, world: *World, chunk: World.Chunk) !void {
        const draw_chunk = DrawChunk{
            .position = world.graph.positions.get(chunk),
            .state = world.chunks.statuses.get(chunk).load_state,
        };
        self.draw_map_mutex.lock();
        defer self.draw_map_mutex.unlock();
        try self.draw_map.put(self.allocator, chunk, draw_chunk);
        // const existing = try self.draw_map.fetchPut(self.allocator, chunk, draw_chunk);
        // if (existing) |_| {
        //     std.log.info("duplicate {}", .{chunk});
        // }
    }

    fn removeDrawChunk(self: *Client, chunk: World.Chunk) void {
        self.draw_map_mutex.lock();
        defer self.draw_map_mutex.unlock();
        _ = self.draw_map.remove(chunk);
    }

    fn drawChunks(self: *Client, dbg: rendering.Debug) void {
        self.draw_map_mutex.lock();
        defer self.draw_map_mutex.unlock();
        dbg.bindCube();
        var iter = self.draw_map.valueIterator();
        while (iter.next()) |draw_chunk| {
            const color = switch (draw_chunk.state) {
                .loading => vec3(.{ 0.5, 0.5, 0.5 }),
                .active => vec3(.{ 1, 1, 1 }),
                .unloading => vec3(.{ 1, 0.5, 0.5 }),
                else => unreachable,
            };
            dbg.drawCubeAssumeBound(draw_chunk.position.cast(f32).addScalar(0.5).mulScalar(World.chunk_width), 1, color);
        }
    }
};
