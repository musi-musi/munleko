const std = @import("std");
const util = @import("util");
const nm = @import("nm");

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

const WorldModel = @import("WorldModel.zig");
const ChunkModel = WorldModel.ChunkModel;

const Allocator = std.mem.Allocator;

const List = std.ArrayListUnmanaged;

const leko = Engine.leko;
const Reference = leko.Reference;

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
pub const LekoFace = struct {
    base: u32,
};

const LekoFaceList = List(LekoFace);

pub const LekoMeshDataPart = enum {
    middle,
    border,
};

pub const LekoMeshData = struct {
    middle_faces: LekoFaceList = .{},
};

pub const LekoMeshDataStore = util.IjoDataStore(ChunkModel, LekoMeshData, struct {
    allocator: Allocator,
    pub fn initData(_: @This(), _: *std.heap.ArenaAllocator) !LekoMeshData {
        return .{};
    }

    pub fn deinitData(self: @This(), data: *LekoMeshData) void {
        data.middle_faces.deinit(self.allocator);
    }
});

pub const ChunkLekoMeshes = struct {
    allocator: Allocator,
    mesh_data: LekoMeshDataStore,

    pub fn init(self: *ChunkLekoMeshes, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .mesh_data = LekoMeshDataStore.initWithContext(allocator, .{ .allocator = allocator }),
        };
    }

    pub fn deinit(self: *ChunkLekoMeshes) void {
        self.mesh_data.deinit();
    }

    pub fn matchDataCapacity(self: *ChunkLekoMeshes, world_model: *const WorldModel) !void {
        try self.mesh_data.matchCapacity(world_model.chunk_models.pool);
    }
};

pub const LekoMeshSystem = struct {
    allocator: Allocator,

    pub fn create(allocator: Allocator) !*LekoMeshSystem {
        const self = try allocator.create(LekoMeshSystem);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    pub fn destroy(self: *LekoMeshSystem) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
    }

    pub fn processChunkModelJob(self: *LekoMeshSystem, world_model: *WorldModel, job: WorldModel.Manager.ChunkModelJob) !void {
        _ = self;
        _ = world_model;
        switch (job.event) {
            .enter => {
                // const chunk_model = enter.chunk_model;
                // const status = world_model.chunk_models.statuses.getPtr(chunk_model);
                // std.time.sleep(10_000_000);
                // status.state.store(.ready, .Monotonic);
            },
        }
    }

    inline fn getLekoFace(self: *LekoMeshSystem, world: *World, comptime traverse_edges: bool, reference: Reference, normal: Cardinal3) ?LekoFace {
        _ = self;
        const leko_data = &world.leko_data;
        const leko_value = leko_data.lekoValueAt(reference);
        if (!leko_data.isSolid(leko_value)) {
            return null;
        }
        const neighbor_reference = (
            if (traverse_edges) reference.incr(world, normal) orelse return null
            else reference.incrUnchecked(normal)
        );
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
        return LekoFace {
            .base = face,
        };
    }
};
