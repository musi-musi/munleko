const std = @import("std");
const util = @import("util");
const nm = @import("nm");
const gl = @import("gl");
const ls = @import("ls");
const oko = @import("oko");

const Atomic = std.atomic.Atomic;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ThreadGroup = util.ThreadGroup;
const AtomicFlag = util.AtomicFlag;

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");
const Assets = Engine.Assets;

const Session = Engine.Session;
const World = Engine.World;
const Chunk = World.Chunk;
const Observer = World.Observer;

const chunk_width = World.chunk_width;

const Scene = @import("Scene.zig");
const WorldModel = @import("WorldModel.zig");
const WorldRenderer = @import("WorldRenderer.zig");
const ChunkModel = WorldModel.ChunkModel;

const leko_mesh = @import("leko_mesh.zig");
const LekoFace = leko_mesh.LekoFace;

const Allocator = std.mem.Allocator;

const List = std.ArrayListUnmanaged;

const leko = Engine.leko;
const Address = leko.Address;
const Reference = leko.Reference;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Cardinal3 = nm.Cardinal3;
const Axis3 = nm.Axis3;

pub const LekoMeshRenderer = @This();

allocator: Allocator,
scene: *Scene,
world_model: *WorldModel,
leko_mesh: LekoMesh,
leko_face_index_buffer: LekoMesh.IndexBuffer,
leko_face_shader: LekoFaceShader,
leko_texture_atlas: LekoTextureAtlas,

pub fn create(allocator: Allocator, scene: *Scene, world_model: *WorldModel) !*LekoMeshRenderer {
    const self = try allocator.create(LekoMeshRenderer);
    self.* = .{
        .allocator = allocator,
        .scene = scene,
        .world_model = world_model,
        .leko_mesh = LekoMesh.create(),
        .leko_face_index_buffer = LekoMesh.IndexBuffer.create(),
        .leko_face_shader = try LekoFaceShader.create(.{}, @embedFile("leko_face.glsl")),
        .leko_texture_atlas = LekoTextureAtlas.create(),
    };
    self.leko_face_index_buffer.data(&.{ 0, 1, 3, 2 }, .static_draw);
    self.leko_mesh.setIndexBuffer(self.leko_face_index_buffer);
    self.leko_face_shader.setSampler(.texture_atlas, 3);
    self.leko_texture_atlas.setFilter(.nearest, .nearest);
    return self;
}

pub fn destroy(self: *LekoMeshRenderer) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.leko_mesh.destroy();
    self.leko_face_index_buffer.destroy();
    self.leko_face_shader.destroy();
    self.leko_texture_atlas.destroy();
}

pub fn applyAssets(self: *LekoMeshRenderer, assets: *const Assets) !void {
    const texture_size = assets.leko_texture_size;
    const texture_count = assets.leko_texture_table.map.count();
    self.leko_texture_atlas.alloc(texture_size, texture_size, texture_count);
    var iter = assets.leko_texture_table.map.valueIterator();
    while (iter.next()) |texture| {
        self.leko_texture_atlas.upload(texture_size, texture_size, texture.index, texture.pixels);
    }
}

const LekoTextureAtlas = gl.TextureRgba8(.array_2d);

pub fn updateAndDrawLekoMeshes(self: *LekoMeshRenderer, draw_chunks: []const WorldRenderer.DrawChunk) void {
    self.leko_mesh.bind();
    self.leko_face_shader.use();
    self.leko_face_shader.setUniform(.light, self.scene.directional_light.v);
    self.leko_face_shader.setUniform(.view, self.scene.camera.view_matrix.v);
    self.leko_face_shader.setUniform(.proj, self.scene.camera.projection_matrix.v);
    self.leko_face_shader.setUniform(.fog_color, self.scene.fog_color.v);
    self.leko_face_shader.setUniform(.fog_start, self.scene.fog_start);
    self.leko_face_shader.setUniform(.fog_end, self.scene.fog_end);
    self.leko_face_shader.setUniform(.fog_power, self.scene.fog_power);
    self.leko_texture_atlas.bind(3);
    var update_count: usize = 0;
    for (draw_chunks) |draw_chunk| {
        if (!self.scene.camera.sphereInInFrustum(draw_chunk.bounds_center, WorldModel.chunk_model_bounds_radius)) {
            continue;
        }
        var was_updated: bool = false;
        const buffer = self.world_model.chunk_leko_meshes.getUpdatedFaceBuffer(draw_chunk.chunk_model, &was_updated);
        if (was_updated) {
            update_count += 1;
        }
        const face_count = self.world_model.chunk_leko_meshes.mesh_data.get(draw_chunk.chunk_model).face_count;
        self.leko_mesh.setBuffer(0, buffer);
        self.leko_face_shader.setUniform(.chunk_origin, draw_chunk.position.mulScalar(chunk_width).cast(f32).v);
        self.leko_mesh.drawInstancedAssumeBound(4, face_count);
    }
    // std.log.info("updated {d} leko meshes", .{update_count});
}

pub const LekoMesh = ls.Mesh(.{
    .buffers = &.{ls.defInstanceBuffer(LekoFace)},
    .primitive_type = .triangle_fan,
});

pub const LekoFaceShader = ls.Shader(.{
    .vert_inputs = LekoMesh.vertex_in_defs,
    .uniforms = &.{
        ls.defUniform("light", .vec3),
        ls.defUniform("view", .mat4),
        ls.defUniform("proj", .mat4),
        ls.defUniform("chunk_origin", .vec3),
        ls.defUniform("fog_color", .vec3),
        ls.defUniform("fog_start", .float),
        ls.defUniform("fog_end", .float),
        ls.defUniform("fog_power", .float),
    },
    .samplers = &.{
        ls.defSampler("texture_atlas", .sampler_2d_array),
    },
    .source_modules = &.{
        leko_face_shader_defs,
    },
});

const leko_face_shader_defs: []const u8 = blk: {
    const Formatter = struct {
        pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
            _ = self;
            try w.print("#define CHUNK_WIDTH {d}\n", .{World.chunk_width});
            try w.print("#define CHUNK_WIDTH_BITS {d}\n", .{World.chunk_width_bits});
            try w.writeAll("const vec3 cube_normals[6] = vec3[6](");
            for (std.enums.values(Cardinal3), 0..) |card_n, i| {
                if (i != 0) {
                    try w.writeAll(", ");
                }
                const normal = Vec3.unitSigned(card_n).v;
                try w.print("vec3({d}, {d}, {d})", .{
                    @floatToInt(i32, normal[0]),
                    @floatToInt(i32, normal[1]),
                    @floatToInt(i32, normal[2]),
                });
            }
            try w.writeAll(");\n");
            try w.writeAll("const vec2 cube_uvs_face[4] = vec2[4](");
            try w.writeAll("vec2(0, 1), vec2(1, 1), vec2(0, 0), vec2(1, 0)");
            try w.writeAll(");\n");
            try w.writeAll("const vec3 cube_umat_texture[6] = vec3[6](");
            for (std.enums.values(Cardinal3), 0..) |card_n, i| {
                if (i != 0) {
                    try w.writeAll(", ");
                }
                const umat = Vec3.unitSigned(leko_mesh.faceNormalToU(card_n));
                try w.print("vec3{}", .{umat});
            }
            try w.writeAll(");\n");
            try w.writeAll("const vec3 cube_vmat_texture[6] = vec3[6](");
            for (std.enums.values(Cardinal3), 0..) |card_n, i| {
                if (i != 0) {
                    try w.writeAll(", ");
                }
                const vmat = Vec3.unitSigned(leko_mesh.faceNormalToV(card_n));
                try w.print("vec3{}", .{vmat});
            }
            try w.writeAll(");\n");
            try w.writeAll("const vec3 cube_positions[24] = vec3[24](");
            var i: u32 = 0;
            for (std.enums.values(Cardinal3)) |card_n| {
                const card_u = leko_mesh.faceNormalToU(card_n);
                const card_v = leko_mesh.faceNormalToV(card_n);
                const n = vertPositionOffset(card_n);
                const u = [2]Vec3{
                    vertPositionOffset(card_u.negate()),
                    vertPositionOffset(card_u),
                };
                const v = [2]Vec3{
                    vertPositionOffset(card_v.negate()),
                    vertPositionOffset(card_v),
                };
                const positions = [4][3]f32{
                    n.add(u[0]).add(v[1]).v,
                    n.add(u[1]).add(v[1]).v,
                    n.add(u[0]).add(v[0]).v,
                    n.add(u[1]).add(v[0]).v,
                };
                for (positions) |position| {
                    if (i != 0) {
                        try w.writeAll(", ");
                    }
                    try w.print("vec3({d}, {d}, {d})", .{
                        @floatToInt(i32, position[0]),
                        @floatToInt(i32, position[1]),
                        @floatToInt(i32, position[2]),
                    });
                    i += 1;
                }
            }
            try w.writeAll(");\n");
        }

        fn vertPositionOffset(comptime cardinal: Cardinal3) Vec3 {
            switch (cardinal.sign()) {
                .positive => return Vec3.unit(cardinal.axis()),
                .negative => return Vec3.zero,
            }
        }
    };
    break :blk std.fmt.comptimePrint("{}", .{Formatter{}});
};
