const std = @import("std");
const nm = @import("nm");
const util = @import("util");
const World = @import("World.zig");

const Allocator = std.mem.Allocator;

const Chunk = World.Chunk;

const Thread = std.Thread;
const ThreadGroup = util.ThreadGroup;
const Atomic = std.atomic.Atomic;
const AtomicFlag = util.AtomicFlag;

const JobQueue = util.JobQueueUnmanaged;
const List = std.ArrayListUnmanaged;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const chunk_width_bits = World.chunk_width_bits;
const chunk_width = World.chunk_width;
const chunk_leko_count = 1 << chunk_width_bits * 3;

pub const LekoValue = enum(u16) { _ };

pub const ChunkLeko = [chunk_leko_count]LekoValue;

pub const ChunkLekoStore = util.IjoDataStoreArenaInit(Chunk, ChunkLeko);

pub const LekoData = struct {
    world: *World,
    chunk_leko: ChunkLekoStore,

    pub fn init(self: *LekoData, world: *World) !void {
        self.* = .{
            .world = world,
            .chunk_leko = ChunkLekoStore.init(world.allocator),
        };
    }

    pub fn deinit(self: *LekoData) void {
        self.chunk_leko.deinit();
    }

    pub fn matchDataCapacity(self: *LekoData) !void {
        try self.chunk_leko.matchCapacity(self.world.chunks.pool);
    }
};

pub const ChunkLoader = struct {
    allocator: Allocator,
    world: *World,

    pub fn create(allocator: Allocator, world: *World) !*ChunkLoader {
        const self = try allocator.create(ChunkLoader);
        self.* = .{
            .allocator = allocator,
            .world = world,
        };
        return self;
    }

    pub fn destroy(self: *ChunkLoader) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
    }

    pub fn loadChunk(self: *ChunkLoader, chunk: Chunk) !void {
        const perlin = nm.Perlin3{};
        const world = self.world;
        const chunk_origin = world.graph.positions.get(chunk).mulScalar(chunk_width).cast(f32);
        const leko = world.leko_data.chunk_leko.get(chunk);
        var i: usize = 0;
        while (i < chunk_leko_count) : (i += 1) {
            const address = Address.initI(i);
            const position = address.localPosition().cast(f32).add(chunk_origin);
            const noise = perlin.sample(position.mulScalar(1 / 32).v);
            const leko_value: u16 = if (noise < 0) 1 else 0;
            leko[i] = @intToEnum(LekoValue, leko_value);
        }

    }
};

pub const UAddress = std.meta.Int(.unsigned, chunk_width_bits * 3);
pub const UChunkWidth = std.meta.Int(.unsigned, chunk_width_bits);

const shr = std.math.shr;
const shl = std.math.shl;

pub const Address = struct {
    v: UAddress = 0,

    pub const zero = Address{};

    pub fn init(comptime T: type, value: [3]T) Address {
        var v: UAddress = @intCast(UChunkWidth, value[0]);
        v = (v << chunk_width_bits) | @intCast(UChunkWidth, value[1]);
        v = (v << chunk_width_bits) | @intCast(UChunkWidth, value[2]);
        return .{ .v = v };
    }

    pub fn initI(value: usize) Address {
        return Address{
            .v = @intCast(UAddress, value),
        };
    }

    pub fn get(self: Address, axis: nm.Axis3) UChunkWidth {
        return @truncate(UChunkWidth, shr(UAddress, self.v, chunk_width_bits * (2 - @enumToInt(axis))));
    }

    pub fn isEdge(self: Address, direction: nm.Cardinal3) bool {
        const w: UChunkWidth = @intCast(UChunkWidth, Chunk.width - 1);
        return switch (direction.sign()) {
            .positive => self.get(direction.axis()) == w,
            .negative => self.get(direction.axis()) == 0,
        };
    }

    /// move this index to the edge of the chunk in `direction`
    pub fn toEdge(self: Address, direction: nm.Cardinal3) Address {
        const w: UChunkWidth = @intCast(UChunkWidth, Chunk.width - 1);
        return switch (direction.sign()) {
            .positive => .{ .v = self.v | single(UChunkWidth, w, direction.axis()).v },
            .negative => .{ .v = self.v & ~single(UChunkWidth, w, direction.axis()).v },
        };
    }

    pub fn edge(comptime T: type, offset: T, direction: nm.Cardinal3) Address {
        const w: UChunkWidth = @intCast(UChunkWidth, Chunk.width - 1);
        return switch (direction.sign()) {
            .positive => .{ .v = single(u32, w - offset, direction.axis()).v },
            .negative => .{ .v = single(u32, offset, direction.axis()).v },
        };
    }

    pub fn single(comptime T: type, value: T, axis: nm.Axis3) Address {
        return Address{
            .v = shl(UAddress, @intCast(UAddress, value), (chunk_width_bits * (2 - @enumToInt(axis)))),
        };
    }

    pub fn localPosition(self: Address) Vec3i {
        return Vec3i.init(.{
            @truncate(UChunkWidth, shr(UAddress, self.v, chunk_width_bits * 2)),
            @truncate(UChunkWidth, shr(UAddress, self.v, chunk_width_bits * 1)),
            @truncate(UChunkWidth, shr(UAddress, self.v, chunk_width_bits * 0)),
        });
    }

    /// increment this index one cell in a cardinal direction
    /// trying to increment out of bounds is UB, only use when in bounds
    pub fn incrUnchecked(self: Address, card: nm.Cardinal3) Address {
        const w: UChunkWidth = @intCast(UChunkWidth, Chunk.width - 1);
        const offset = switch (card) {
            .x_pos => init(UChunkWidth, .{ 1, 0, 0 }),
            .x_neg => init(UChunkWidth, .{ w, 0, 0 }),
            .y_pos => init(UChunkWidth, .{ 0, 1, 0 }),
            .y_neg => init(UChunkWidth, .{ w, w, 0 }),
            .z_pos => init(UChunkWidth, .{ 0, 0, 1 }),
            .z_neg => init(UChunkWidth, .{ w, w, w }),
        };
        return .{ .v = self.v +% offset.v };
    }

    /// decrement this index one cell in a cardinal direction
    /// trying to increment out of bounds is UB, only use when in bounds
    pub fn decrUnchecked(self: Address, card: nm.Cardinal3) Address {
        return self.incrUnchecked(card.negate());
    }
};

pub const Reference = struct {
    chunk: Chunk,
    address: Address,

    pub fn init(chunk: Chunk, address: Address) Reference {
        return Reference{
            .chunk = chunk,
            .address = address,
        };
    }

    pub fn initGlobalPosition(world: *World, position: Vec3i) ?Reference {
        const chunk_position = position.divScalar(chunk_width);
        const chunk = world.graph.chunkAt(chunk_position) orelse return null;
        const local_position = position.sub(chunk_position.mulScalar(chunk_width));
        return init(chunk, Address.init(i32, local_position.v));
    }

    pub fn incrUnchecked(self: Reference, direction: nm.Cardinal3) Reference {
        return init(self.chunk, self.address.incrUnchecked(direction));
    }

    pub fn decrUnchecked(self: Reference, direction: nm.Cardinal3) Reference {
        return init(self.chunk, self.address.decrUnchecked(direction));
    }

    pub fn incr(self: Reference, world: *World, direction: nm.Cardinal3) ?Reference {
        if (!self.address.isEdge(direction)) {
            return self.incrUnchecked(direction);
        }
        const neighbor = world.graph.neighborChunk(self.chunk, direction) orelse return null;
        return init(neighbor, self.address.toEdge(direction.negate()));
    }

    pub fn decr(self: Reference, world: *World, direction: nm.Cardinal3) ?Reference {
        return self.incr(world, direction.negate());
    }
};
