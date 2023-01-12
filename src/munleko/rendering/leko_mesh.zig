const std = @import("std");
const util = @import("util");
const nm = @import("nm");
const gl = @import("gl");
const ls = @import("ls");

const Atomic = std.atomic.Atomic;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ThreadGroup = util.ThreadGroup;
const AtomicFlag = util.AtomicFlag;

const Client = @import("../Client.zig");
const Engine = @import("../Engine.zig");

const Session = Engine.Session;
const World = Engine.World;
const Chunk = World.Chunk;
const Observer = World.Observer;

const chunk_width = World.chunk_width;

const Scene = @import("Scene.zig");
const WorldModel = @import("WorldModel.zig");
const WorldRenderer = @import("WorldRenderer.zig");
const ChunkModel = WorldModel.ChunkModel;

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

pub const LekoMeshRenderer = struct {
    allocator: Allocator,
    scene: *Scene,
    world_model: *WorldModel,
    leko_mesh: LekoMesh,
    leko_face_index_buffer: LekoMesh.IndexBuffer,
    leko_face_shader: LekoFaceShader,

    pub fn create(allocator: Allocator, scene: *Scene, world_model: *WorldModel) !*LekoMeshRenderer {
        const self = try allocator.create(LekoMeshRenderer);
        self.* = .{
            .allocator = allocator,
            .scene = scene,
            .world_model = world_model,
            .leko_mesh = LekoMesh.create(),
            .leko_face_index_buffer = LekoMesh.IndexBuffer.create(),
            .leko_face_shader = try LekoFaceShader.create(.{}, @embedFile("leko_face.glsl")),
        };
        self.leko_face_index_buffer.data(&.{0, 2, 3, 1}, .static_draw);
        // self.leko_face_index_buffer.data(&.{0, 1, 3, 0, 3, 2}, .static_draw);
        self.leko_mesh.setIndexBuffer(self.leko_face_index_buffer);
        return self;
    }

    pub fn destroy(self: *LekoMeshRenderer) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.leko_mesh.destroy();
        self.leko_face_index_buffer.destroy();
        self.leko_face_shader.destroy();
    }

    pub fn updateAndDrawLekoMeshes(self: *LekoMeshRenderer, draw_chunks: []const WorldRenderer.DrawChunk) void {
        self.leko_mesh.bind();
        self.leko_face_shader.use();
        self.leko_face_shader.setUniform(.light, self.scene.directional_light.v);
        self.leko_face_shader.setUniform(.view, self.scene.camera_view.v);
        self.leko_face_shader.setUniform(.proj, self.scene.camera_projection.v);
        self.leko_face_shader.setUniform(.fog_color, self.scene.fog_color.v);
        self.leko_face_shader.setUniform(.fog_start, self.scene.fog_start);
        self.leko_face_shader.setUniform(.fog_end, self.scene.fog_end);
        self.leko_face_shader.setUniform(.fog_power, self.scene.fog_power);
        for (draw_chunks) |draw_chunk| {
            const buffer = self.world_model.chunk_leko_meshes.getUpdatedFaceBuffer(draw_chunk.chunk_model);
            const face_count = self.world_model.chunk_leko_meshes.mesh_data.get(draw_chunk.chunk_model).face_count;
            self.leko_mesh.setBuffer(0, buffer);
            self.leko_face_shader.setUniform(.chunk_origin, draw_chunk.position.mulScalar(chunk_width).cast(f32).v);
            self.leko_mesh.drawInstancedAssumeBound(4, face_count);
        }
    }
};

/// ```
///     0 --- 1
///     | \   |   ^
///     |  \  |   |
///     |   \ |   v
///     2 --- 3   + u -- >
/// ```
///  base = 0b 000000 xxxxx yyyyy zzzzz nnn aaaaaaaa
///  - xyz  position of leko
///  - n    0-5 face index; Cardinal3 (face normal)
///  - a    ao strength per vertex, packed 0b33221100
pub const LekoFace = struct {
    base: u32,
};

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
            for (std.enums.values(Cardinal3)) |card_n, i| {
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
            for (std.enums.values(Cardinal3)) |card_n, i| {
                if (i != 0) {
                    try w.writeAll(", ");
                }
                const umat = Vec3.unitSigned(cardU(card_n));
                try w.print("vec3{}", .{ umat });
            }
            try w.writeAll(");\n");
            try w.writeAll("const vec3 cube_vmat_texture[6] = vec3[6](");
            for (std.enums.values(Cardinal3)) |card_n, i| {
                if (i != 0) {
                    try w.writeAll(", ");
                }
                const vmat = Vec3.unitSigned(cardV(card_n));
                try w.print("vec3{}", .{ vmat });
            }
            try w.writeAll(");\n");
            try w.writeAll("const vec3 cube_positions[24] = vec3[24](");
            var i: u32 = 0;
            for (std.enums.values(Cardinal3)) |card_n| {
                const card_u = cardU(card_n);
                const card_v = cardV(card_n);
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

const LekoFaceList = std.ArrayList(LekoFace);

pub const LekoMeshDataPart = enum {
    middle,
    border,
};

pub const LekoMeshData = struct {
    middle_faces: LekoFaceList,
    face_count: usize = 0,
    is_dirty: AtomicFlag = .{},
};

pub const LekoMeshDataStore = util.IjoDataStore(ChunkModel, LekoMeshData, struct {
    allocator: Allocator,
    pub fn initData(self: @This(), _: *std.heap.ArenaAllocator) !LekoMeshData {
        return LekoMeshData{
            .middle_faces = std.ArrayList(LekoFace).init(self.allocator),
        };
    }

    pub fn deinitData(_: @This(), data: *LekoMeshData) void {
        data.middle_faces.deinit();
    }
});

pub const LekoFaceBuffer = gl.Buffer(LekoFace);

pub const LekoFaceBufferStore = util.IjoDataStore(ChunkModel, ?LekoFaceBuffer, struct {
    pub fn initData(_: @This(), _: *std.heap.ArenaAllocator) !?LekoFaceBuffer {
        return null;
    }
    pub fn deinitData(_: @This(), buffer: *?LekoFaceBuffer) void {
        if (buffer.*) |b| {
            b.destroy();
        }
    }
});

pub const ChunkLekoMeshes = struct {
    allocator: Allocator,
    mesh_data: LekoMeshDataStore,
    face_buffers: LekoFaceBufferStore,

    pub fn init(self: *ChunkLekoMeshes, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .mesh_data = LekoMeshDataStore.initWithContext(allocator, .{ .allocator = allocator }),
            .face_buffers = LekoFaceBufferStore.init(allocator),
        };
    }

    pub fn deinit(self: *ChunkLekoMeshes) void {
        self.mesh_data.deinit();
        self.face_buffers.deinit();
    }

    pub fn matchDataCapacity(self: *ChunkLekoMeshes, world_model: *const WorldModel) !void {
        try self.mesh_data.matchCapacity(world_model.chunk_models.pool);
        try self.face_buffers.matchCapacity(world_model.chunk_models.pool);
    }

    pub fn getUpdatedFaceBuffer(self: *ChunkLekoMeshes, chunk_model: ChunkModel) LekoFaceBuffer {
        const buffer = self.getFaceBuffer(chunk_model);
        const data = self.mesh_data.getPtr(chunk_model);
        if (data.is_dirty.get()) {
            data.is_dirty.set(false);
            data.face_count = data.middle_faces.items.len;
            buffer.data(data.middle_faces.items, .static_draw);
        }
        return buffer;
    }

    fn getFaceBuffer(self: *ChunkLekoMeshes, chunk_model: ChunkModel) LekoFaceBuffer {
        const buffer_ptr = self.face_buffers.getPtr(chunk_model);
        if (buffer_ptr.*) |buffer| {
            return buffer;
        }
        const buffer = LekoFaceBuffer.create();
        buffer_ptr.* = buffer;
        return buffer;
    }
};

pub const LekoMeshSystem = struct {
    allocator: Allocator,
    world_model: *WorldModel,

    pub fn create(allocator: Allocator, world_model: *WorldModel) !*LekoMeshSystem {
        const self = try allocator.create(LekoMeshSystem);
        self.* = .{
            .allocator = allocator,
            .world_model = world_model,
        };
        return self;
    }

    pub fn destroy(self: *LekoMeshSystem) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
    }

    pub fn processChunkModelJob(self: *LekoMeshSystem, job: WorldModel.Manager.ChunkModelJob) !void {
        const chunk = job.chunk;
        const chunk_model = job.chunk_model;
        const mesh_data = self.world_model.chunk_leko_meshes.mesh_data.getPtr(chunk_model);
        switch (job.event) {
            .enter => {
                try self.generateMiddleFaces(self.world_model.world, chunk, mesh_data);
            },
        }
        mesh_data.is_dirty.set(true);
    }

    fn generateMiddleFaces(self: *LekoMeshSystem, world: *World, chunk: Chunk, mesh_data: *LekoMeshData) !void {
        mesh_data.middle_faces.clearRetainingCapacity();
        var x: u32 = 1;
        while (x < chunk_width - 1) : (x += 1) {
            var y: u32 = 1;
            while (y < chunk_width - 1) : (y += 1) {
                var z: u32 = 1;
                while (z < chunk_width - 1) : (z += 1) {
                    const reference = Reference.init(chunk, Address.init(u32, .{ x, y, z }));
                    inline for (comptime std.enums.values(Cardinal3)) |normal| {
                        if (self.getLekoFace(world, false, reference, normal)) |leko_face| {
                            try mesh_data.middle_faces.append(leko_face);
                        }
                    }
                }
            }
        }
        // std.log.info("{d} faces", .{mesh_data.middle_faces.items.len});
    }

    inline fn getLekoFace(self: *LekoMeshSystem, world: *World, comptime traverse_edges: bool, reference: Reference, normal: Cardinal3) ?LekoFace {
        _ = self;
        const leko_data = &world.leko_data;
        const leko_value = leko_data.lekoValueAt(reference);
        if (!leko_data.isSolid(leko_value)) {
            return null;
        }
        const neighbor_reference = (if (traverse_edges) reference.incr(world, normal) orelse return null else reference.incrUnchecked(normal));
        const neighbor_leko_value = leko_data.lekoValueAt(neighbor_reference);
        if (leko_data.isSolid(neighbor_leko_value)) {
            return null;
        }
        return encodeLekoFace(reference.address, normal, 0);
    }

    fn encodeLekoFace(address: leko.Address, normal: Cardinal3, ao: u8) LekoFace {
        var face: u32 = address.v;
        face = (face << 3) | @as(u32, @enumToInt(normal));
        face = (face << 8) | ao;
        return LekoFace{
            .base = face,
        };
    }
};
