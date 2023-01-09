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
        // var rng = std.rand.DefaultPrng.init(0xBABE);
        // const r = rng.random();
        const leko = world.leko_data.chunk_leko.get(chunk);
        var i: usize = 0;
        var x: f32 = 0;
        while (x < chunk_width) : (x += 1) {
            var y: f32 = 0;
            while (y < chunk_width) : (y += 1) {
                var z: f32 = 0;
                while (z < chunk_width) : (z += 1) {
                    defer i += 1;
                    var position = vec3(.{x, y, z}).add(chunk_origin);
                    const noise = perlin.sample(position.mulScalar(1/32).v);
                    const leko_value: u16 = if (noise < 0) 1 else 0;
                    leko[i] = @intToEnum(LekoValue, leko_value);
                }
            }
        }
        // std.log.info("load {}", .{chunk});
        // if (status.pending_load_state == World.ChunkLoadState.unloading) {
        //     world.chunks.stopUsing(chunk);
        //     continue;
        // }
        // std.time.sleep(10000000 + @enumToInt(chunk) * 100);

    }

};
