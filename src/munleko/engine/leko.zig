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
        const world = self.world;
        var rng = std.rand.DefaultPrng.init(0xBABE);
        const r = rng.random();
        const leko = world.leko_data.chunk_leko.get(chunk);
        for (leko) |*l| {
            l.* = @intToEnum(LekoValue, r.int(u1));
        }
        // std.log.info("load {}", .{chunk});
        // if (status.pending_load_state == World.ChunkLoadState.unloading) {
        //     world.chunks.stopUsing(chunk);
        //     continue;
        // }
        // std.time.sleep(10000000 + @enumToInt(chunk) * 100);

    }

};
