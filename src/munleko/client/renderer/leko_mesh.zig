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

const Client = @import("../../Client.zig");
const Engine = @import("../../Engine.zig");

const Session = Engine.Session;
const World = Engine.World;
const Assets = Engine.Assets;

const Chunk = World.Chunk;
const Observer = World.Observer;

const chunk_width = World.chunk_width;

const Resources = @import("Resources.zig");

const Scene = @import("Scene.zig");
const WorldModel = @import("WorldModel.zig");
const WorldRenderer = @import("WorldRenderer.zig");
const ChunkModel = WorldModel.ChunkModel;

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const List = std.ArrayListUnmanaged;

const leko = Engine.leko;
const Address = leko.Address;
const Reference = leko.Reference;
const LekoValue = leko.LekoValue;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Cardinal3 = nm.Cardinal3;
const Axis3 = nm.Axis3;

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
pub const LekoFace = extern struct {
    base: u32,
    color: [3]f32,
    texture_index: u32,
};

pub fn faceNormalToU(normal: Cardinal3) Cardinal3 {
    return switch (normal) {
        .x_pos => .z_neg,
        .x_neg => .z_pos,
        .y_pos => .z_pos,
        .y_neg => .z_neg,
        .z_pos => .x_pos,
        .z_neg => .x_neg,
    };
}

pub fn faceNormalToV(normal: Cardinal3) Cardinal3 {
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
    border_faces: LekoFaceList,
    face_count: usize = 0,
    is_dirty: AtomicFlag = .{},
    mutex: Mutex = .{},
};

pub const LekoMeshDataStore = util.IjoDataStore(ChunkModel, LekoMeshData, struct {
    allocator: Allocator,
    pub fn initData(self: @This(), _: *std.heap.ArenaAllocator) !LekoMeshData {
        return LekoMeshData{
            .middle_faces = std.ArrayList(LekoFace).init(self.allocator),
            .border_faces = std.ArrayList(LekoFace).init(self.allocator),
        };
    }

    pub fn deinitData(_: @This(), data: *LekoMeshData) void {
        data.middle_faces.deinit();
        data.border_faces.deinit();
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

    material_table: ?*const LekoMaterialTable = null,

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

    pub fn applyResources(self: *ChunkLekoMeshes, resources: *Resources) !void {
        self.material_table = &resources.leko_material.material_table;
    }

    pub fn getUpdatedFaceBuffer(self: *ChunkLekoMeshes, chunk_model: ChunkModel, was_updated: *bool) LekoFaceBuffer {
        const buffer = self.getFaceBuffer(chunk_model);
        const data = self.mesh_data.getPtr(chunk_model);
        if (!data.mutex.tryLock()) {
            return buffer;
        }
        defer data.mutex.unlock();
        if (!data.is_dirty.get()) {
            return buffer;
        }
        data.is_dirty.set(false);
        was_updated.* = true;
        const middle_faces = data.middle_faces.items;
        const border_faces = data.border_faces.items;
        data.face_count = middle_faces.len + border_faces.len;
        buffer.alloc(data.face_count, .static_draw);
        buffer.subData(middle_faces, 0);
        buffer.subData(border_faces, middle_faces.len);
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
        @setRuntimeSafety(false);
        const chunk = job.chunk;
        const chunk_model = job.chunk_model;
        const mesh_data = self.world_model.chunk_leko_meshes.mesh_data.getPtr(chunk_model);
        mesh_data.mutex.lock();
        defer mesh_data.mutex.unlock();
        const task_flags = job.task_flags;
        var mesh_is_dirty = false;
        if (task_flags.contains(.leko_mesh_generate_middle)) {
            try self.generateMiddleFaces(self.world_model.world, chunk, mesh_data);
            mesh_is_dirty = true;
        }
        if (task_flags.contains(.leko_mesh_generate_border)) {
            try self.generateBorderFaces(self.world_model.world, chunk, mesh_data);
            mesh_is_dirty = true;
        }
        if (mesh_is_dirty) {
            mesh_data.is_dirty.set(true);
        }
    }

    fn generateMiddleFaces(self: *LekoMeshSystem, world: *World, chunk: Chunk, mesh_data: *LekoMeshData) !void {
        mesh_data.middle_faces.clearAndFree();
        var x: u32 = 1;
        while (x < chunk_width - 1) : (x += 1) {
            var y: u32 = 1;
            while (y < chunk_width - 1) : (y += 1) {
                var z: u32 = 1;
                while (z < chunk_width - 1) : (z += 1) {
                    try self.appendLekoFaces(&mesh_data.middle_faces, world, chunk, false, x, y, z);
                }
            }
        }
    }

    fn generateBorderFaces(self: *LekoMeshSystem, world: *World, chunk: Chunk, mesh_data: *LekoMeshData) !void {
        mesh_data.border_faces.clearAndFree();
        const range = comptime blk: {
            var result: [chunk_width]u32 = undefined;
            for (&result, 0..) |*x, i| {
                x.* = i;
            }
            break :blk result;
        };
        const max = chunk_width - 1;
        inline for (.{ 0, max }) |x| {
            for (range) |y| {
                for (range) |z| {
                    try self.appendLekoFaces(&mesh_data.border_faces, world, chunk, true, x, y, z);
                }
            }
        }

        for (range[1..max]) |x| {
            inline for (.{ 0, max }) |y| {
                for (range) |z| {
                    try self.appendLekoFaces(&mesh_data.border_faces, world, chunk, true, x, y, z);
                }
            }
            for (range[1..max]) |y| {
                inline for (.{ 0, max }) |z| {
                    try self.appendLekoFaces(&mesh_data.border_faces, world, chunk, true, x, y, z);
                }
            }
        }
    }

    fn appendLekoFaces(self: *LekoMeshSystem, list: *std.ArrayList(LekoFace), world: *World, chunk: Chunk, comptime traverse_edges: bool, x: u32, y: u32, z: u32) !void {
        const reference = Reference.init(chunk, Address.init(u32, .{ x, y, z }));
        const material = self.getMaterial(reference) orelse return;
        inline for (comptime std.enums.values(Cardinal3)) |normal| {
            if (self.getLekoFaceBase(world, traverse_edges, reference, normal)) |base| {
                try list.append(.{
                    .base = base,
                    .color = material.color.v,
                    .texture_index = material.texture_index,
                });
            }
        }
    }

    inline fn getLekoFaceBase(self: *LekoMeshSystem, world: *World, comptime traverse_edges: bool, reference: Reference, normal: Cardinal3) ?u32 {
        const neighbor_reference = (if (traverse_edges) reference.incr(world, normal) orelse return null else reference.incrUnchecked(normal));
        if (self.getMaterial(neighbor_reference) != null) {
            return null;
        }
        const ao = switch (normal) {
            inline else => |n| self.computeAO(world, traverse_edges, reference, n),
        };
        const base = encodeLekoFaceBase(reference.address, normal, ao);
        return base;
    }

    fn encodeLekoFaceBase(address: leko.Address, normal: Cardinal3, ao: u8) u32 {
        var base: u32 = address.v;
        base = (base << 3) | @as(u32, @intFromEnum(normal));
        base = (base << 8) | ao;
        return base;
    }

    fn getMaterial(self: LekoMeshSystem, reference: Reference) ?FaceMaterial {
        const leko_value = self.world_model.world.leko_data.lekoValueAt(reference);
        const material_table = self.world_model.chunk_leko_meshes.material_table orelse return null;
        return material_table.getForLekoValue(leko_value);
    }

    fn computeAO(self: LekoMeshSystem, world: *World, comptime traverse_edges: bool, reference: Reference, comptime normal: Cardinal3) u8 {
        _ = self;
        const u = comptime faceNormalToU(normal);
        const v = comptime faceNormalToV(normal);

        var r: Reference = undefined;
        if (traverse_edges) {
            r = reference.incr(world, normal) orelse return 0;
        } else {
            r = reference.incrUnchecked(normal);
        }

        const Move = struct {
            sign: enum { incr, decr },
            direction: Cardinal3,
        };

        const moves = [8]Move{
            .{ .sign = .decr, .direction = u },
            .{ .sign = .incr, .direction = v },
            .{ .sign = .incr, .direction = u },
            .{ .sign = .incr, .direction = u },
            .{ .sign = .decr, .direction = v },
            .{ .sign = .decr, .direction = v },
            .{ .sign = .decr, .direction = u },
            .{ .sign = .decr, .direction = u },
        };

        var neighbors: u8 = 0;
        inline for (moves, 0..) |move, i| {
            if (traverse_edges) {
                switch (move.sign) {
                    .incr => r = r.incr(world, move.direction) orelse return 0,
                    .decr => r = r.decr(world, move.direction) orelse return 0,
                }
            } else {
                switch (move.sign) {
                    .incr => r = r.incrUnchecked(move.direction),
                    .decr => r = r.decrUnchecked(move.direction),
                }
            }
            neighbors |= @as(u8, @intFromBool(isOpaque(world, r))) << i;
        }
        return ao_table[neighbors];
    }

    /// ```
    ///  | 1 |  2  | 3 |
    ///  | - 0 --- 1 - |
    ///  |   | \   |   |    ^
    ///  | 0 |  \  | 4 |    |
    ///  |   |   \ |   |    v
    ///  | - 2 --- 3 - |    + u ->
    ///  | 7 |  6  | 5 |
    /// ```
    const ao_table: [256]u8 = blk: {
        @setEvalBranchQuota(1_000_000);
        var table = std.mem.zeroes([256]u8);
        var i: u32 = 0;
        while (i < 256) : (i += 1) {
            var neighbors = @as(u8, @intCast(i));
            for ([4]u3{ 0, 1, 3, 2 }) |vert| {
                const vert_neighbors = neighbors & 0b111;
                neighbors = std.math.rotr(u8, neighbors, 2);
                const ao: u8 = switch (vert_neighbors) {
                    0b000 => 0,
                    0b010 => 1,
                    0b001 => 1,
                    0b100 => 1,
                    0b011 => 2,
                    0b110 => 2,
                    0b101 => 3,
                    0b111 => 3,
                    else => unreachable,
                };
                table[i] |= ao << 2 * vert;
            }
        }
        break :blk table;
    };

    fn isOpaque(world: *World, reference: Reference) bool {
        return world.leko_data.lekoValueAt(reference) != .empty;
    }
};

pub const FaceMaterial = struct {
    color: Vec3,
    texture_index: u32,
};

pub const LekoMaterialTable = struct {
    allocator: Allocator,
    list: std.ArrayListUnmanaged(?FaceMaterial) = .{},

    pub fn init(self: *LekoMaterialTable, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
        };
        errdefer self.deinit();
        // material for the empty leko type
        try self.list.append(self.allocator, null);
    }

    pub fn deinit(self: *LekoMaterialTable) void {
        self.list.deinit(self.allocator);
    }

    pub fn addMaterialsFromLekoAssets(self: *LekoMaterialTable, assets: *const Assets) !void {
        for (assets.leko_type_table.list.items[1..]) |leko_type| {
            const name = leko_type.name;
            const leko_asset = assets.leko_table.getByName(name) orelse unreachable;
            if (!leko_asset.is_visible) {
                try self.list.append(self.allocator, null);
                continue;
            }
            const texture_index = (if (assets.leko_texture_table.getByName(leko_asset.texture_name)) |leko_texture_asset| (leko_texture_asset.index) else (0));
            try self.list.append(self.allocator, FaceMaterial{
                .color = leko_asset.color,
                .texture_index = @as(u32, @intCast(texture_index)),
            });
        }
    }

    pub fn getForLekoValue(self: LekoMaterialTable, value: LekoValue) ?FaceMaterial {
        const index = @intFromEnum(value);
        if (index >= self.list.items.len) {
            return null;
        }
        return self.list.items[index];
    }
};
