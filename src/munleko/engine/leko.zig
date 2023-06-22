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

pub const ChunkLekoStore = util.IjoDataStoreArenaInit(Chunk, ChunkLeko);

pub const LekoData = struct {
    world: *World,
    chunk_leko: ChunkLekoStore,
    leko_types: LekoTypeTable,

    pub fn init(self: *LekoData, world: *World) !void {
        self.* = .{
            .world = world,
            .chunk_leko = ChunkLekoStore.init(world.allocator),
            .leko_types = undefined,
        };
        try self.leko_types.init(world.allocator);
    }

    pub fn deinit(self: *LekoData) void {
        self.chunk_leko.deinit();
        self.leko_types.deinit();
    }

    pub fn matchDataCapacity(self: *LekoData) !void {
        try self.chunk_leko.matchCapacity(self.world.chunks.pool);
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
        @setRuntimeSafety(false);
        const perlin = nm.Perlin3{};
        const world = self.world;
        const chunk_origin = world.graph.positions.get(chunk).mulScalar(chunk_width);
        const leko = world.leko_data.chunk_leko.get(chunk);
        const types = &world.leko_data.leko_types;

        const stone = types.getValueForName("stone") orelse .empty;
        const dirt = types.getValueForName("dirt") orelse .empty;
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

        const seed: u64 = (@intCast(u64, @truncate(u16, @bitCast(u32, chunk_origin.v[0]))) << 32 |
            @intCast(u64, @truncate(u16, @bitCast(u32, chunk_origin.v[1]))) << 16 |
            @intCast(u64, @truncate(u16, @bitCast(u32, chunk_origin.v[2]))));
        var rng = std.rand.DefaultPrng.init(seed);
        const r = rng.random();
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
            if ((material_noise + r.float(f32) / 20) < 0.1) {
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

    fn init(self: *LekoTypeTable, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .arena = Arena.init(allocator),
        };

        errdefer self.deinit();
        try self.addLekoType("empty", .{
            .is_solid = false,
        });
    }

    fn deinit(self: *LekoTypeTable) void {
        self.arena.deinit();
        self.list.deinit(self.allocator);
        self.name_map.deinit(self.allocator);
    }

    pub fn addLekoType(self: *LekoTypeTable, name: []const u8, properties: LekoType.Properties) !void {
        const index = @intCast(u16, self.list.items.len);
        const leko_value = @intToEnum(LekoValue, index);
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
        const index = @enumToInt(value);
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
        return @truncate(UChunkWidth, shr(UAddress, self.v, chunk_width_bits * @as(u32, 2 - @enumToInt(axis))));
    }

    pub fn isEdge(self: Address, direction: nm.Cardinal3) bool {
        const w: UChunkWidth = @intCast(UChunkWidth, chunk_width - 1);
        return switch (direction.sign()) {
            .positive => self.get(direction.axis()) == w,
            .negative => self.get(direction.axis()) == 0,
        };
    }

    /// move this index to the edge of the chunk in `direction`
    pub fn toEdge(self: Address, direction: nm.Cardinal3) Address {
        const w: UChunkWidth = @intCast(UChunkWidth, chunk_width - 1);
        return switch (direction.sign()) {
            .positive => .{ .v = self.v | single(UChunkWidth, w, direction.axis()).v },
            .negative => .{ .v = self.v & ~single(UChunkWidth, w, direction.axis()).v },
        };
    }

    pub fn edge(comptime T: type, offset: T, direction: nm.Cardinal3) Address {
        const w: UChunkWidth = @intCast(UChunkWidth, chunk_width - 1);
        return switch (direction.sign()) {
            .positive => .{ .v = single(u32, w - offset, direction.axis()).v },
            .negative => .{ .v = single(u32, offset, direction.axis()).v },
        };
    }

    pub fn single(comptime T: type, value: T, axis: nm.Axis3) Address {
        return Address{
            .v = shl(UAddress, @intCast(UAddress, value), (chunk_width_bits * @as(u32, 2 - @enumToInt(axis)))),
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
        const w: UChunkWidth = @intCast(UChunkWidth, chunk_width - 1);
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

pub fn raycastGeneric(
    world: *World,
    origin: Vec3,
    direction: Vec3,
    comptime Return: type,
    context: anytype,
    comptime condition: fn (@TypeOf(context), *World, Reference, GridRaycastIterator) ?Return,
) ?Return {
    var iter = GridRaycastIterator.init(origin, direction);
    var reference = Reference.initGlobalPosition(world, iter.cell) orelse return null;
    while (true) {
        if (condition(context, world, reference, iter)) |ret| {
            return ret;
        }
        iter.next();
        reference = reference.incr(World, iter.move) orelse return null;
    }
}

pub const GridRaycastIterator = struct {
    /// starting position of the ray
    origin: Vec3,
    /// normalized direction of the ray
    direction: Vec3,
    /// the last cell we hit
    cell: Vec3i,
    /// the total distance the raycast has travelled from `origin`
    distance: f32 = 0,
    /// the direction the raycast moved to get to the current cell from the previous cell
    /// undefined until next is called for the first time
    /// negate this direction to get the normal of the face we just hit
    move: Cardinal3 = undefined,
    // i really dont remember what these two values are exactly but they're part of the state
    // that determines what the next move is
    t_max: Vec3,
    t_delta: Vec3,

    pub fn init(origin: Vec3, direction: Vec3) GridRaycastIterator {
        const dir = direction.norm() orelse Vec3.zero;
        const dx2 = dir.v[0] * dir.v[0];
        const dy2 = dir.v[1] * dir.v[1];
        const dz2 = dir.v[2] * dir.v[2];
        var t_delta = Vec3.zero;
        if (dx2 != 0) t_delta.v[0] = std.math.sqrt(1 + (dy2 + dz2) / dx2);
        if (dy2 != 0) t_delta.v[0] = std.math.sqrt(1 + (dx2 + dy2) / dy2);
        if (dz2 != 0) t_delta.v[0] = std.math.sqrt(1 + (dx2 + dy2) / dz2);
        const origin_floor = origin.floor();
        var t_max = Vec3.init(.{
            (if (dir.v[0] > 0) (origin_floor.v[0] + 1 - origin.v[0]) else origin.v[0] - origin_floor.v[0]) * t_delta.v[0],
            (if (dir.v[1] > 0) (origin_floor.v[1] + 1 - origin.v[1]) else origin.v[1] - origin_floor.v[1]) * t_delta.v[1],
            (if (dir.v[2] > 0) (origin_floor.v[2] + 1 - origin.v[2]) else origin.v[2] - origin_floor.v[2]) * t_delta.v[2],
        });
        if (dir.v[0] == 0) t_max.v[0] = std.math.inf(f32);
        if (dir.v[1] == 0) t_max.v[1] = std.math.inf(f32);
        if (dir.v[2] == 0) t_max.v[2] = std.math.inf(f32);
        return GridRaycastIterator{
            .origin = origin,
            .cell = origin_floor.cast(i32),
            .direction = dir,
            .t_max = t_max,
            .t_delta = t_delta,
        };
    }

    pub fn next(self: *GridRaycastIterator) void {
        const min = self.t_max.minComponent();
        const axis = min.axis;
        self.t_max.ptrMut(axis).* += self.t_delta.get(axis);
        if (self.direction.get(axis) < 0) {
            self.cell.ptrMut(axis).* -= 1;
            self.updateDistance(axis, .negative);
            switch (axis) {
                inline else => |a| self.move = comptime Cardinal3.init(a, .negative),
            }
        } else {
            self.cell.ptrMut(axis).* += 1;
            self.updateDistance(axis, .positive);
            switch (axis) {
                inline else => |a| self.move = comptime Cardinal3.init(a, .positive),
            }
        }
    }

    fn updateDistance(self: *GridRaycastIterator, axis: nm.Axis3, comptime sign: nm.Sign) void {
        var distance = @intToFloat(f32, self.cell.get(axis)) - self.origin.get(axis);
        distance += (1 - sign.scalar(f32)) / 2;
        self.distance = distance / self.direction.get(axis);
    }
};

const Bounds3 = nm.Bounds3;
const Range3i = nm.Range3i;

pub const physics = struct {
    pub const LekoTypeTest = fn (?LekoType) bool;

    pub fn lekoTypeIsSolid(leko_type: ?LekoType) bool {
        if (leko_type) |lt| {
            return lt.properties.is_solid;
        }
        return true;
    }

    fn invertLekoTypeTest(comptime test_fn: LekoTypeTest) LekoTypeTest {
        return (struct {
            fn f(leko_type: LekoType) bool {
                return !test_fn(leko_type);
            }
        }.f);
    }

    pub fn testPosition(world: *World, position: Vec3i, comptime test_fn: LekoTypeTest) bool {
        const leko_value = world.leko_data.lekoValueAtPosition(position) orelse return test_fn(null);
        const leko_type = world.leko_data.leko_types.getForValue(leko_value);
        return test_fn(leko_type);
    }

    pub fn testRangeAny(world: *World, range: Range3i, comptime test_fn: LekoTypeTest) bool {
        var iter = range.iterate();
        while (iter.next()) |position| {
            if (testPosition(world, position, test_fn)) {
                return true;
            }
        }
        return false;
    }

    pub fn testRangeAll(world: *World, range: Range3i, comptime test_fn: LekoTypeTest) bool {
        return !testRangeAny(world, range, invertLekoTypeTest(test_fn));
    }

    /// return the distance `bounds` would need to move along `direction` to snap the leading edge to the grid in `direction`
    /// distance returned is never negative
    pub fn boundsSnapDistance(bounds: Bounds3, comptime direction: Cardinal3) f32 {
        const axis = comptime direction.axis();
        const center = bounds.center.get(axis);
        const radius = bounds.radius.get(axis);
        switch (comptime direction.sign()) {
            .positive => {
                const x = center + radius;
                return @ceil(x) - x;
            },
            .negative => {
                const x = center - radius;
                return x - @floor(x);
            },
        }
    }

    pub fn moveBoundsAxis(world: *World, bounds: *Bounds3, move: f32, comptime axis: Axis3, comptime is_solid: LekoTypeTest) ?f32 {
        if (move < 0) {
            return moveBoundsDirection(world, bounds, -move, comptime Cardinal3.init(axis, .negative), is_solid);
        } else {
            return moveBoundsDirection(world, bounds, move, comptime Cardinal3.init(axis, .positive), is_solid);
        }
    }

    const skin_width = 1e-3;

    fn moveBoundsDirection(world: *World, bounds: *Bounds3, move: f32, comptime direction: Cardinal3, comptime is_solid: LekoTypeTest) ?f32 {
        std.debug.assert(move >= 0);
        var distance_moved: f32 = 0;
        const axis = comptime direction.axis();
        const sign = comptime direction.sign();
        const initial_snap = boundsSnapDistance(bounds.*, direction);
        if (initial_snap > move) {
            bounds.center.ptrMut(axis).* += sign.scalar(f32) * move;
            return null;
        }
        bounds.center.ptrMut(axis).* += sign.scalar(f32) * initial_snap;
        distance_moved += initial_snap;
        while (distance_moved < move) {
            if (testBoundsDirection(world, bounds.*, direction, is_solid)) {
                bounds.center.ptrMut(axis).* -= sign.scalar(f32) * skin_width;
                return distance_moved;
            }
            if (move - distance_moved > 1) {
                distance_moved += 1;
                switch (sign) {
                    .positive => bounds.center.ptrMut(axis).* += 1,
                    .negative => bounds.center.ptrMut(axis).* -= 1,
                }
            } else {
                switch (sign) {
                    .positive => bounds.center.ptrMut(axis).* += (move - distance_moved),
                    .negative => bounds.center.ptrMut(axis).* -= (move - distance_moved),
                }
                break;
            }
        }
        return null;
    }

    fn testBoundsDirection(world: *World, bounds: Bounds3, comptime direction: Cardinal3, comptime test_fn: LekoTypeTest) bool {
        const range = boundsFaceRange(bounds, direction);
        return testRangeAny(world, range, test_fn);
    }

    fn boundsFaceRange(bounds: Bounds3, comptime direction: Cardinal3) Range3i {
        const axis = comptime direction.axis();
        const sign = comptime direction.sign();
        const u: Axis3 = switch (axis) {
            .x => .y,
            .y => .x,
            .z => .x,
        };
        const v: Axis3 = switch (axis) {
            .x => .z,
            .y => .z,
            .z => .y,
        };
        var range: Range3i = undefined;
        range.min.ptrMut(u).* = @floatToInt(i32, @floor(bounds.center.get(u) - bounds.radius.get(u)));
        range.min.ptrMut(v).* = @floatToInt(i32, @floor(bounds.center.get(v) - bounds.radius.get(v)));
        range.max.ptrMut(u).* = @floatToInt(i32, @ceil(bounds.center.get(u) + bounds.radius.get(u)));
        range.max.ptrMut(v).* = @floatToInt(i32, @ceil(bounds.center.get(v) + bounds.radius.get(v)));
        switch (sign) {
            .positive => {
                const x = @floatToInt(i32, @ceil(bounds.center.get(axis) + bounds.radius.get(axis)));
                range.min.ptrMut(axis).* = x;
                range.max.ptrMut(axis).* = x + 1;
            },
            .negative => {
                const x = @floatToInt(i32, @floor(bounds.center.get(axis) - bounds.radius.get(axis)));
                range.min.ptrMut(axis).* = x - 1;
                range.max.ptrMut(axis).* = x;
            },
        }
        return range;
    }
};
