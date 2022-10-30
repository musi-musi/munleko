const std = @import("std");
const ls = @import("ls");
const gl = @import("gl");
const nm = @import("nm");

const Vec3 = nm.Vec3;
const Cardinal3 = nm.Cardinal3;

const Vert = struct {
    position: [3]f32,
    normal: [3]f32,
};

const Mesh = ls.Mesh(.{
    .buffers = &.{ ls.defVertexBuffer(Vert)}
});

const Shader = ls.Shader(.{
    .vert_inputs = Mesh.vertex_in_defs,
    .uniforms = &.{
        ls.defUniform("light", .vec3),
        ls.defUniform("view", .mat4),
        ls.defUniform("proj", .mat4),
        ls.defUniform("color", .vec3),
        ls.defUniform("position", .vec3),
        ls.defUniform("radius", .float),
    },
});

pub const Debug = struct {

    shader: Shader,
    mesh: Mesh,
    cube_buffers: Buffers,

    pub fn init() !Debug {
        const shader = try Shader.create(.{}, @embedFile("debug.glsl"));
        const cube_buffers = generateCubeBuffers();
        const mesh = Mesh.create();
        return Debug {
            .shader = shader,
            .mesh = mesh,
            .cube_buffers = cube_buffers,
        };
    }

    pub fn deinit(self: Debug) void {
        self.shader.destroy();
        self.mesh.destroy();
        self.cube_buffers.destroy();
    }

    pub fn start(self: Debug) void {
        self.shader.use();
        self.mesh.bind();
    }

    pub fn drawCube(self: Debug, position: Vec3, radius: f32, color: Vec3) void {
        self.shader.setUniform(.position, position.v);
        self.shader.setUniform(.radius, radius);
        self.shader.setUniform(.color, color.v);
        self.mesh.setBuffer(0, self.cube_buffers.verts);
        self.mesh.setIndexBuffer(self.cube_buffers.indices);
        self.mesh.drawAssumeBound(36);
    }

    pub fn setLight(self: Debug, light: Vec3) void {
        self.shader.setUniform(.light, light.v);
    }

    pub fn setView(self: Debug, view: nm.Mat4) void {
        self.shader.setUniform(.view, view.v);
    }

    pub fn setProj(self: Debug, proj: nm.Mat4) void {
        self.shader.setUniform(.proj, proj.v);
    }

    pub const Buffers = struct {
        verts: gl.Buffer(Vert),
        indices: gl.Buffer(u32),

        pub fn create() Buffers {
            return Buffers {
                .verts = gl.Buffer(Vert).create(),
                .indices = gl.Buffer(u32).create(),
            };
        }

        pub fn destroy(self: Buffers) void {
            self.verts.destroy();
            self.indices.destroy();
        }
    };

    fn generateCubeBuffers() Buffers {
        const buffers = Buffers.create();

        @setEvalBranchQuota(1_000_000);
        const verts = comptime
            generateFace(.x_pos) ++
            generateFace(.x_neg) ++
            generateFace(.y_pos) ++
            generateFace(.y_neg) ++
            generateFace(.z_pos) ++
            generateFace(.z_neg);

        buffers.verts.data(&verts, .static_draw);

        var indices: [36]u32 = undefined;
        var i: u32 = 0;
        var f: u32 = 0;
        while (i < 36) : (i += 6) {
            indices[i + 0] = f + 0;
            indices[i + 1] = f + 1;
            indices[i + 2] = f + 3;
            indices[i + 3] = f + 0;
            indices[i + 4] = f + 3;
            indices[i + 5] = f + 2;
            f += 4;
        }

        buffers.indices.data(&indices, .static_draw);

        return buffers;
    }

    fn generateFace(comptime n: Cardinal3) [4]Vert {
        const vec = Vec3.unitSigned;
        const up = cardU(n);
        const vp = cardV(n);
        const un = up.neg();
        const vn = vp.neg();
        return .{
            .{
                .position = vec(n).add(vec(un)).add(vec(vp)).v,
                .normal = vec(n).v,
            },
            .{
                .position = vec(n).add(vec(up)).add(vec(vp)).v,
                .normal = vec(n).v,
            },
            .{
                .position = vec(n).add(vec(un)).add(vec(vn)).v,
                .normal = vec(n).v,
            },
            .{
                .position = vec(n).add(vec(up)).add(vec(vn)).v,
                .normal = vec(n).v,
            },
        };
    }

    fn cardU(normal: Cardinal3) Cardinal3 {
        return switch (normal) {
            .x_pos => .z_neg,
            .x_neg => .z_pos,
            .y_pos => .z_pos,
            .y_neg => .z_neg,
            .z_pos => .x_pos,
            .z_neg => .x_neg,
        };
    }

    fn cardV(normal: Cardinal3) Cardinal3 {
        return switch (normal) {
            .x_pos => .y_pos,
            .x_neg => .y_pos,
            .y_pos => .x_pos,
            .y_neg => .x_pos,
            .z_pos => .y_pos,
            .z_neg => .y_pos,
        };
    }
};
