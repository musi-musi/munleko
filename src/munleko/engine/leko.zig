const std = @import("std");
const nm = @import("nm");
const util = @import("util");
const World = @import("World.zig");
const Assets = @import("Assets.zig");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const Chunk = World.Chunk;

const Thread = std.Thread;
const ThreadGroup = util.ThreadGroup;
const Atomic = std.atomic.Atomic;
const AtomicFlag = util.AtomicFlag;
const Mutex = Thread.Mutex;

const JobQueue = util.JobQueueUnmanaged;
const List = std.ArrayListUnmanaged;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Axis3 = nm.Axis3;
const Sign = nm.Sign;
const Cardinal3 = nm.Cardinal3;

const chunk_width_bits = World.chunk_width_bits;
const chunk_width = World.chunk_width;
const chunk_leko_count = 1 << chunk_width_bits * 3;

pub const LekoValue = enum(u16) { empty = 0, _ };

pub const ChunkLeko = [chunk_leko_count]LekoValue;

pub const ChunkLekoMeta = struct {
    generation: u32 = 0,
};

pub const ChunkLekoStore = util.IjoDataStoreArenaInit(Chunk, ChunkLeko);
pub const ChunkLekoMetaStore = util.IjoDataStoreDefaultInit(Chunk, ChunkLekoMeta);

pub const LekoEvents = util.Events(union(enum) {
    leko_edit: LekoEditEvent,
});

pub const LekoEditEvent = struct {
    reference: Reference,
    old_value: LekoValue,
    new_value: LekoValue,
};

pub const LekoData = struct {
    world: *World,
    chunk_leko: ChunkLekoStore,
    chunk_meta: ChunkLekoMetaStore,
    leko_types: *LekoTypeTable,
    events: LekoEvents,
    events_mutex: Mutex = .{},

    pub fn init(self: *LekoData, world: *World, leko_type_table: *LekoTypeTable) !void {
        const allocator = world.allocator;
        self.* = .{
            .world = world,
            .chunk_leko = ChunkLekoStore.init(allocator),
            .chunk_meta = ChunkLekoMetaStore.init(allocator),
            .leko_types = leko_type_table,
            .events = LekoEvents.init(allocator),
        };
    }

    pub fn deinit(self: *LekoData) void {
        self.chunk_leko.deinit();
        self.chunk_meta.deinit();
        self.events.deinit();
    }

    pub fn matchDataCapacity(self: *LekoData) !void {
        try self.chunk_leko.matchCapacity(self.world.chunks.pool);
        try self.chunk_meta.matchCapacity(self.world.chunks.pool);
    }

    pub fn lekoValueAt(self: *LekoData, reference: Reference) LekoValue {
        return self.chunk_leko.get(reference.chunk).*[reference.address.v];
    }

    pub fn isSolid(self: *LekoData, value: LekoValue) bool {
        if (self.leko_types.getForValue(value)) |leko_type| {
            return leko_type.properties.is_solid;
        }
        return true;
    }

    pub fn lekoValueAtPosition(self: *LekoData, position: Vec3i) ?LekoValue {
        if (Reference.initGlobalPosition(self.world, position)) |reference| {
            return self.lekoValueAt(reference);
        }
        return null;
    }

    pub fn editLekoAt(self: *LekoData, reference: Reference, new_value: LekoValue) !void {
        const meta = self.chunk_meta.getPtr(reference.chunk);
        meta.generation +%= 1;
        const ptr = &self.chunk_leko.get(reference.chunk).*[reference.address.v];
        const old_value = ptr.*;
        ptr.* = new_value;
        self.events_mutex.lock();
        defer self.events_mutex.unlock();
        try self.events.post(.leko_edit, .{
            .reference = reference,
            .old_value = old_value,
            .new_value = new_value,
        });
    }

    /// return true if successful
    pub fn editLekoAtPosition(self: *LekoData, position: Vec3i, new_value: LekoValue) !bool {
        if (Reference.initGlobalPosition(self.world, position)) |reference| {
            try self.editLekoAt(reference, new_value);
            return true;
        }
        return false;
    }

    pub fn clearEvents(self: *LekoData) void {
        self.events_mutex.lock();
        defer self.events_mutex.unlock();
        self.events.clearAll();
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
        const meta = self.world.leko_data.chunk_meta.getPtr(chunk);
        meta.generation = 0;
        @setRuntimeSafety(false);
        const perlin = nm.Perlin3{};
        const world = self.world;
        const chunk_origin = world.graph.positions.get(chunk).mulScalar(chunk_width);
        const leko = world.leko_data.chunk_leko.get(chunk);
        const types = world.leko_data.leko_types;

        const stone = types.getValueForName("stone") orelse .empty;
        const dirt = types.getValueForName("dirt") orelse .empty;
        const brick = types.getValueForName("brick") orelse .empty;
        const sand = types.getValueForName("sand") orelse .empty;
        _ = sand;
        _ = brick;
        // const pallete = [_]LekoValue{
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("stone") orelse .empty,
        //     types.getValueForName("dirt") orelse .empty,
        //     types.getValueForName("dirt") orelse .empty,
        //     types.getValueForName("dirt") orelse .empty,
        //     types.getValueForName("dirt") orelse .empty,
        //     types.getValueForName("dirt") orelse .empty,
        //     types.getValueForName("grass") orelse .empty,
        //     types.getValueForName("grass") orelse .empty,
        //     // types.getValueForName("sand") orelse .empty,
        // };

        const seed: u64 = (@as(u64, @intCast(@as(u16, @truncate(@as(u32, @bitCast(chunk_origin.v[0])))))) << 32 |
            @as(u64, @intCast(@as(u16, @truncate(@as(u32, @bitCast(chunk_origin.v[1])))))) << 16 |
            @as(u64, @intCast(@as(u16, @truncate(@as(u32, @bitCast(chunk_origin.v[2])))))));
        var rng = std.rand.DefaultPrng.init(seed);
        const r = rng.random();
        _ = r;
        var i: usize = 0;
        while (i < chunk_leko_count) : (i += 1) {
            const address = Address.initI(i);
            const leko_position = address.localPosition().add(chunk_origin);
            const sample_position = leko_position.cast(f32).mul(vec3(.{ 0.5, 1, 0.5 }));
            const noise = perlin.sample(sample_position.mulScalar(0.025).v);
            const material_noise = perlin.sample(sample_position.addScalar(7439).mulScalar(0.025).v);
            // _ = noise;
            // const leko_value: u16 = if (r.float(f32) > 0.95) 1 else 0;
            if (noise > 0.15) {
                leko[i] = .empty;
                continue;
            }
            if ((material_noise) < 0.1) {
                // if ((material_noise + r.float(f32) / 20) < 0.1) {
                leko[i] = stone;
            } else {
                leko[i] = dirt;
            }
            // leko[i] = pallete[@intCast(usize, @mod(leko_position.v[1], @intCast(i32, pallete.len)))];
        }
    }
};

const LekoAsset = Assets.LekoAsset;
const LekoAssetTable = Assets.LekoAssetTable;

pub const LekoType = struct {
    value: LekoValue,
    name: []const u8,
    properties: Properties,

    pub const Properties = struct {
        is_solid: bool,
    };
};

pub const LekoTypeTable = struct {
    allocator: Allocator,
    arena: Arena,
    list: List(LekoType) = .{},
    name_map: std.StringHashMapUnmanaged(*LekoType) = .{},

    pub fn init(self: *LekoTypeTable, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .arena = Arena.init(allocator),
        };

        errdefer self.deinit();
        try self.addLekoType("empty", .{
            .is_solid = false,
        });
    }

    pub fn deinit(self: *LekoTypeTable) void {
        self.arena.deinit();
        self.list.deinit(self.allocator);
        self.name_map.deinit(self.allocator);
    }

    pub fn addLekoType(self: *LekoTypeTable, name: []const u8, properties: LekoType.Properties) !void {
        const index = @as(u16, @intCast(self.list.items.len));
        const leko_value = @as(LekoValue, @enumFromInt(index));
        const owned_name = try self.arena.allocator().dupe(u8, name);
        const leko_type = LekoType{
            .value = leko_value,
            .name = owned_name,
            .properties = properties,
        };
        try self.list.append(self.allocator, leko_type);
        try self.name_map.put(self.allocator, owned_name, &self.list.items[index]);
    }

    pub fn addLekoTypesFromAssetTable(self: *LekoTypeTable, asset_table: LekoAssetTable) !void {
        var iter = asset_table.map.iterator();
        while (iter.next()) |kvp| {
            const name = kvp.key_ptr.*;
            const asset = kvp.value_ptr.*;
            try self.addLekoType(name, .{
                .is_solid = asset.is_solid,
            });
        }
    }

    pub fn getForValue(self: LekoTypeTable, value: LekoValue) ?LekoType {
        const index = @intFromEnum(value);
        if (index >= self.list.items.len) {
            return null;
        }
        return self.list.items[index];
    }

    pub fn getForName(self: LekoTypeTable, name: []const u8) ?LekoType {
        if (self.name_map.get(name)) |leko_type| {
            return leko_type.*;
        }
        return null;
    }

    pub fn getValueForName(self: LekoTypeTable, name: []const u8) ?LekoValue {
        if (self.getForName(name)) |leko_type| {
            return leko_type.value;
        } else {
            return null;
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
        var v: UAddress = @as(UChunkWidth, @intCast(value[0]));
        v = (v << chunk_width_bits) | @as(UChunkWidth, @intCast(value[1]));
        v = (v << chunk_width_bits) | @as(UChunkWidth, @intCast(value[2]));
        return .{ .v = v };
    }

    pub fn initI(value: usize) Address {
        return Address{
            .v = @as(UAddress, @intCast(value)),
        };
    }

    pub fn get(self: Address, axis: nm.Axis3) UChunkWidth {
        return @as(UChunkWidth, @truncate(shr(UAddress, self.v, chunk_width_bits * @as(u32, 2 - @intFromEnum(axis)))));
    }

    pub fn isBorder(self: Address) bool {
        const w: UChunkWidth = @as(UChunkWidth, @intCast(chunk_width - 1));
        if (self.get(.x) == 0) return true;
        if (self.get(.x) == w) return true;
        if (self.get(.y) == 0) return true;
        if (self.get(.y) == w) return true;
        if (self.get(.z) == 0) return true;
        if (self.get(.z) == w) return true;
        return false;
    }

    pub fn isEdge(self: Address, direction: nm.Cardinal3) bool {
        const w: UChunkWidth = @as(UChunkWidth, @intCast(chunk_width - 1));
        return switch (direction.sign()) {
            .positive => self.get(direction.axis()) == w,
            .negative => self.get(direction.axis()) == 0,
        };
    }

    /// move this index to the edge of the chunk in `direction`
    pub fn toEdge(self: Address, direction: nm.Cardinal3) Address {
        const w: UChunkWidth = @as(UChunkWidth, @intCast(chunk_width - 1));
        return switch (direction.sign()) {
            .positive => .{ .v = self.v | single(UChunkWidth, w, direction.axis()).v },
            .negative => .{ .v = self.v & ~single(UChunkWidth, w, direction.axis()).v },
        };
    }

    pub fn edge(comptime T: type, offset: T, direction: nm.Cardinal3) Address {
        const w: UChunkWidth = @as(UChunkWidth, @intCast(chunk_width - 1));
        return switch (direction.sign()) {
            .positive => .{ .v = single(u32, w - offset, direction.axis()).v },
            .negative => .{ .v = single(u32, offset, direction.axis()).v },
        };
    }

    pub fn single(comptime T: type, value: T, axis: nm.Axis3) Address {
        return Address{
            .v = shl(UAddress, @as(UAddress, @intCast(value)), (chunk_width_bits * @as(u32, 2 - @intFromEnum(axis)))),
        };
    }

    pub fn localPosition(self: Address) Vec3i {
        return Vec3i.init(.{
            @as(UChunkWidth, @truncate(shr(UAddress, self.v, chunk_width_bits * 2))),
            @as(UChunkWidth, @truncate(shr(UAddress, self.v, chunk_width_bits * 1))),
            @as(UChunkWidth, @truncate(shr(UAddress, self.v, chunk_width_bits * 0))),
        });
    }

    /// increment this index one cell in a cardinal direction
    /// trying to increment out of bounds is UB, only use when in bounds
    pub fn incrUnchecked(self: Address, card: nm.Cardinal3) Address {
        const w: UChunkWidth = @as(UChunkWidth, @intCast(chunk_width - 1));
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
        const chunk_position = position.divFloorScalar(chunk_width);
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
