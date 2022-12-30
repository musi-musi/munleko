const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Engine = @import("../Engine.zig");
const Session = @import("Session.zig");
const leko = @import("leko.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const List = std.ArrayListUnmanaged;

const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Atomic = std.atomic.Atomic;
const AtomicFlag = util.AtomicFlag;
const ResetEvent = Thread.ResetEvent;

const World = @This();

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;

const Range3i = nm.Range3i;

pub const Chunk = util.Ijo("world chunk");
const ChunkPool = util.IjoPool(Chunk);

pub const chunk_width_bits = 5;
pub const chunk_width = 1 << chunk_width_bits;

allocator: Allocator,
chunks: Chunks = undefined,
observers: Observers = undefined,

pub fn create(allocator: Allocator) !*World {
    const self = try allocator.create(World);
    self.* = .{
        .allocator = allocator,
    };
    try self.chunks.init(self);
    try self.observers.init(self);
    return self;
}

pub fn destroy(self: *World) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.chunks.deinit();
    self.observers.deinit();
}

pub const ChunkLoadState = enum {
    deleted,
    loading,
    active,
    unloading,
};

pub const ChunkStatus = struct {
    load_state: ChunkLoadState = .deleted,
};

const ChunkStatusStore = util.IjoDataStoreDefaultInit(Chunk, ChunkStatus);

pub const Chunks = struct {
    world: *World,
    statuses: ChunkStatusStore,

    fn init(self: *Chunks, world: *World) !void {
        self.* = .{
            .world = world,
            .chunk_status_store = ChunkStatusStore.init(world.allocator),
        };
    }

    fn deinit(self: *Chunks) void {
        self.chunk_status_store.deinit();
    }
};

pub const Observer = util.Ijo("world observer");
const ObserverPool = util.IjoPool(Observer);

pub const ObserverState = enum(u8) {
    deleted,
    creating,
    active,
    deleting,
};

const ObserverStatus = struct {
    state: Atomic(ObserverState) = .{ .value = .deleted },
    is_dirty: AtomicFlag = .{},
};

pub const ObserverStatusStore = util.IjoDataStoreDefaultInit(Observer, ObserverStatus);

pub const Observers = struct {
    world: *World,
    statuses: ObserverStatusStore,

    list: List(Observer) = .{},
    mutex: Mutex = .{},

    fn init(self: *Observers, world: *World) !void {
        self.* = .{
            .world = world,
            .statuses = ObserverStatusStore.init(world.allocator),
        };
    }

    fn deinit(self: *Observers) void {
        self.statuses.deinit();
        self.list.deinit(self.world.allocator);
    }

    fn count(self: *Observers) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.list.items.len;
    }

    fn atIndex(self: *Observers, i: usize) Observer {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.list.items[i];
    }

    fn swapRemove(self: *Observers, i: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ =  self.list.swapRemove(i);
    }

};



pub const Manager = struct {
    allocator: Allocator,
    world: *World,

    thread: Thread = undefined,
    is_running: AtomicFlag = .{},

    pub fn create(allocator: Allocator, world: *World) !*Manager {
        const self = try allocator.create(Manager);
        self.* = .{
            .allocator = allocator,
            .world = world,
        };
        return self;
    }

    pub fn destroy(self: *Manager) void {
        const allocator = self.allocator;
        defer allocator.destroy(self);
    }

    pub fn OnWorldUpdateFn(comptime Context: type) type {
        return fn (Context, *World) anyerror!void;
    }

    pub fn start(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        const Context = @TypeOf(context);
        const thread_main = (struct {
            fn f(s: *Manager, c: Context) !void {
                try s.threadMain(c, on_update_fn);
            }
        }).f;

        if (self.is_running.get()) {
            @panic("world manager is already running");
        }
        self.is_running.set(true);
        self.thread = try Thread.spawn(.{}, thread_main, .{self, context});
    }

    pub fn stop(self: *Manager) void {
        if (!self.is_running.get()) {
            return;
        }
        self.is_running.set(false);
        self.thread.join();
    }

    fn threadMain(self: *Manager, context: anytype, comptime on_update_fn: OnWorldUpdateFn(@TypeOf(context))) !void {
        while (self.is_running.get()) {
            try self.processDirtyObservers();
            try on_update_fn(context, self.world);
        }
    }

    fn processDirtyObservers(self: *Manager) !void {
        const world = self.world;
        const observers = &world.observers;
        var i: usize = 0;
        while (i < observers.count()) : (i += 1) {
            const observer = observers.atIndex(i);
            _ = observer;
        }
    }
};
