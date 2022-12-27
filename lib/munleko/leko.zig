const std = @import("std");
const nm = @import("nm");
const util = @import("util");
const World = @import("World.zig");

const Allocator = std.mem.Allocator;

const Chunk = World.Chunk;

const Thread = std.Thread;
const ThreadGroup = util.ThreadGroup;
const Atomic = std.atomic.Atomic;

const JobQueue = util.JobQueueUnmanaged;
const List = std.ArrayListUnmanaged;

const chunk_width_bits = World.chunk_width_bits;
const chunk_width = World.chunk_width;
const chunk_leko_count = 1 << chunk_width_bits * 3;

pub const LekoValue = enum(u16) { _ };

pub const ChunkLeko = [chunk_leko_count]LekoValue;

pub const ChunkLekoStore = util.IjoDataStoreArenaInit(Chunk, ChunkLeko);

pub const LekoData = struct {
    allocator: Allocator,
    chunk_leko: ChunkLekoStore,

    pub fn init(self: *LekoData, allocator: Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .chunk_leko = ChunkLekoStore.init(allocator),
        };
    }

    pub fn deinit(self: *LekoData) void {
        self.chunk_leko.deinit();
    }

    fn matchDataCapacity(self: *LekoData, world: *World) !void {
        try self.chunk_leko.matchCapacity(world.chunks.pool);
    }
};

pub const LekoLoadSystem = struct {
    allocator: Allocator,
    load_group: util.ThreadGroup = undefined,
    load_group_is_running: Atomic(bool) = Atomic(bool).init(false),

    chunk_job_queue: ChunkJobQueue = .{},

    const ChunkJobQueue = JobQueue(Chunk);

    pub fn create(allocator: Allocator) !*LekoLoadSystem {
        const self = try allocator.create(LekoLoadSystem);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    pub fn destroy(self: *LekoLoadSystem) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.stop();
    }

    pub fn start(self: *LekoLoadSystem, world: *World) !void {
        if (self.load_group_is_running.load(.Monotonic)) {
            @panic("leko load thread group is already running");
        }
        self.load_group_is_running.store(true, .Monotonic);
        self.load_group = try ThreadGroup.spawnCpuCount(self.allocator, 0.5, .{}, loadGroupMain, .{ self, world });
    }

    pub fn stop(self: *LekoLoadSystem) void {
        if (self.load_group_is_running.load(.Monotonic)) {
            self.chunk_job_queue.flush(self.allocator);
            self.load_group_is_running.store(false, .Monotonic);
            self.load_group.join();
        }
    }

    pub fn onWorldUpdate(self: *LekoLoadSystem, world: *World) !void {
        const leko = &world.leko;
        try leko.matchDataCapacity(world);
        for (world.chunks.load_state_events.get(.loading)) |event| {
            world.chunks.startUsing(event.chunk);
            try self.chunk_job_queue.push(self.allocator, event.chunk, event.priority);
        }
    }

    fn loadGroupMain(self: *LekoLoadSystem, world: *World) !void {
        var rng = std.rand.DefaultPrng.init(0xBABE);
        const r = rng.random();
        while (self.load_group_is_running.load(.Monotonic)) {
            if (self.chunk_job_queue.pop()) |node| {
                const chunk = node.item;
                const status = world.chunks.statuses.get(chunk);
                std.debug.assert(status.load_state == .loading);
                std.debug.assert(status.pending_load_state == World.ChunkLoadState.active or status.pending_load_state == World.ChunkLoadState.unloading);
                const leko = world.leko.chunk_leko.get(chunk);

                for (leko) |*l| {
                    l.* = @intToEnum(LekoValue, r.int(u1));
                }
                // std.log.info("load {}", .{chunk});
                // if (status.pending_load_state == World.ChunkLoadState.unloading) {
                //     world.chunks.stopUsing(chunk);
                //     continue;
                // }
                // std.time.sleep(10000000 + @enumToInt(chunk) * 100);
                world.chunks.stopUsing(chunk);
            }
        }
    }
};
