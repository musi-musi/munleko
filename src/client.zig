const std = @import("std");
const window = @import("window");
const gl = @import("gl");
const ls = @import("ls");

const musileko = @import("musileko.zig");

const Allocator = std.mem.Allocator;
const Session = musileko.Session;
const Window = window.Window;

const TestShader = ls.Shader(.{
    .vert_inputs = &.{
        ls.defVertIn(0, "position", .vec3),
        ls.defVertIn(1, "uv", .vec2),
    },
});


pub fn main() !void {
    // try TestShader.create(.{}, "[insert code here]");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    try window.init();
    defer window.deinit();

    var client: Client = undefined;
    try client.init(allocator);
    defer client.deinit();

    try client.run();

}

pub const Client = struct {

    window: Window,
    session: Session,

    pub fn init(self: *Client, allocator: Allocator) !void {
        self.window = Window.init(allocator);
        try self.session.init(
            allocator,
            Session.Callbacks.init(
                self,
                tick,
            ),
        );
    }

    pub fn deinit(self: *Client) void {
        self.window.deinit();
        self.session.deinit();
    }

    pub fn run(self: *Client) !void {
        try self.window.create(.{});
        defer self.window.destroy();
        self.window.makeContextCurrent();
        self.window.setVsync(.disabled);
        try gl.init(window.getGlProcAddress);
        gl.viewport(.{self.window.width, self.window.height});

        const Vert = struct {
            position: [2]f32,
            color: [3]f32,
        };

        const Mesh = ls.Mesh(.{
            .buffers = &.{ ls.defVertexBuffer(Vert)}
        });

        const VertBuffer = Mesh.Buffer(0);

        const mesh = Mesh.create();
        defer mesh.destroy();

        const verts = VertBuffer.create();
        defer verts.destroy();
        verts.data(&.{
            .{
                .position = .{-0.5, -0.5},
                .color = .{ 1.0, 0.5, 0.5},
            },
            .{
                .position = .{ 0.0,  0.5},
                .color = .{ 0.5, 1.0, 0.5},
            },
            .{
                .position = .{ 0.5, -0.5},
                .color = .{ 0.5, 0.5, 1.0},
            },
        }, .static_draw);

        const indices = Mesh.IndexBuffer.create();
        defer indices.destroy();
        indices.data(&.{ 0, 1, 2 }, .static_draw);

        mesh.setBuffer(0, verts);
        mesh.setIndexBuffer(indices);

        mesh.bind();

        gl.clearColor(.{0, 0, 0, 1});

        const Shader = ls.Shader(.{
            .vert_inputs = Mesh.vertex_in_defs,
        });

        const shader = try Shader.create(.{}, @embedFile("test.glsl"));
        defer shader.destroy();

        shader.use();

        var timer = try std.time.Timer.start();
        var frames: u32 = 0;
        while (self.window.nextFrame()) {
            for(self.window.events.get(.framebuffer_size)) |size| {
                gl.viewport(size);
            }
            gl.clear(.color_depth);
            mesh.drawAssumeBound(3);
            
            const t_ns = timer.read();
            if (t_ns > std.time.ns_per_s) {
                timer.start_time += std.time.ns_per_s;
                std.log.info("fps: {d}", .{frames});
                frames = 0;
            }
            frames += 1;
        }
    }

    pub fn tick(self: *Client, session: *Session) !void {
        _ = self;
        if (session.tick_count % 100 == 0) {
            std.log.debug("tick {d}", .{ session.tick_count });
        }
    }

};