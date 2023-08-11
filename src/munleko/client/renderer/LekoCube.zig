const std = @import("std");
const util = @import("util");
const nm = @import("nm");
const gl = @import("gl");
const ls = @import("ls");

const Cardinal3 = nm.Cardinal3;
const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Mat4 = nm.Mat4;

const LekoCube = @This();

const Renderer = @import("../Renderer.zig");

const leko_mesh = @import("leko_mesh.zig");

pub const Vertex = extern struct {
    position: [3]f32,
    normal: u32,
    uv: [2]f32,
};

pub const VertexBuffer = gl.Buffer(Vertex);
pub const IndexBuffer = Mesh.IndexBuffer;

pub const Mesh = ls.Mesh(.{
    .buffers = &.{ls.defVertexBuffer(Vertex)},
});

pub const Shader = ls.Shader(.{
    .vert_inputs = Mesh.vertex_in_defs,
    .uniforms = &.{
        ls.defUniform("light", .vec3),
        ls.defUniform("model", .mat4),
        ls.defUniform("view", .mat4),
        ls.defUniform("proj", .mat4),
        ls.defUniform("texture_index", .uint),
        ls.defUniform("uv_scale", .float),
    },
    .samplers = &.{
        ls.defSampler("texture_atlas", .sampler_2d_array),
    },
});

shader: Shader,
mesh: Mesh,
vertex_buffer: VertexBuffer,
index_buffer: IndexBuffer,

pub fn init() !LekoCube {
    const mesh = Mesh.create();
    errdefer mesh.destroy();
    const vertex_buffer = VertexBuffer.create();
    errdefer vertex_buffer.destroy();
    vertex_buffer.data(comptime &generateVerts(), .static_draw);
    const index_buffer = IndexBuffer.create();
    errdefer index_buffer.destroy();
    index_buffer.data(comptime &generateIndices(), .static_draw);
    mesh.setBuffer(0, vertex_buffer);
    mesh.setIndexBuffer(index_buffer);
    return LekoCube{
        .shader = undefined,
        .mesh = mesh,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
    };
}

pub fn deinit(self: *LekoCube) void {
    // self.shader.destroy();
    self.mesh.destroy();
    self.vertex_buffer.destroy();
    self.index_buffer.destroy();
}

fn generateVerts() [24]Vertex {
    @setEvalBranchQuota(1_000_000);
    return generateFaceVerts(.x_pos) ++
        generateFaceVerts(.x_neg) ++
        generateFaceVerts(.y_pos) ++
        generateFaceVerts(.y_neg) ++
        generateFaceVerts(.z_pos) ++
        generateFaceVerts(.z_neg);
}

fn generateFaceVerts(comptime n: Cardinal3) [4]Vertex {
    const u_pos = leko_mesh.faceNormalToU(n);
    const v_pos = leko_mesh.faceNormalToV(n);
    const u_neg = u_pos.negate();
    const v_neg = v_pos.negate();
    const vec = Vec3.unitSigned;
    return .{
        .{
            .position = vec(n).add(vec(u_neg)).add(vec(v_pos)).divScalar(2).v,
            .normal = @intFromEnum(n),
            .uv = .{ 0, 1 },
        },
        .{
            .position = vec(n).add(vec(u_pos)).add(vec(v_pos)).divScalar(2).v,
            .normal = @intFromEnum(n),
            .uv = .{ 1, 1 },
        },
        .{
            .position = vec(n).add(vec(u_neg)).add(vec(v_neg)).divScalar(2).v,
            .normal = @intFromEnum(n),
            .uv = .{ 0, 0 },
        },
        .{
            .position = vec(n).add(vec(u_pos)).add(vec(v_neg)).divScalar(2).v,
            .normal = @intFromEnum(n),
            .uv = .{ 1, 0 },
        },
    };
}

fn generateIndices() [36]u32 {
    return generateFaceIndices(0) ++
        generateFaceIndices(1) ++
        generateFaceIndices(2) ++
        generateFaceIndices(3) ++
        generateFaceIndices(4) ++
        generateFaceIndices(5);
}

fn generateFaceIndices(comptime face_i: u32) [6]u32 {
    return .{
        face_i * 6 + 0,
        face_i * 6 + 1,
        face_i * 6 + 3,
        face_i * 6 + 0,
        face_i * 6 + 3,
        face_i * 6 + 2,
    };
}
