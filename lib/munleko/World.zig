const std = @import("std");
const util = @import("util");
const nm = @import("nm");

const Engine = @import("Engine.zig");
const Session = @import("Session.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const List = std.ArrayListUnmanaged;

const Mutex = std.Thread.Mutex;

const World = @This();

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Vec3i = nm.Vec3i;
const vec3i = nm.vec3i;


allocator: Allocator,

chunk_arena: ArenaAllocator,

chunks: List(*Chunk) = .{},
chunk_id_pool: Chunk.IdPool = .{},
chunk_map: ChunkMap = .{},



pub fn create(allocator: Allocator) !*World {
    const self = try allocator.create(World);
    self.* =  .{
        .allocator = allocator,
        .chunk_arena = ArenaAllocator.init(allocator),
    };
    return self;
}

pub fn destroy(self: *World) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);

    self.chunk_arena.deinit();

    self.chunks.deinit(self.allocator);
    self.chunk_id_pool.deinit(self.allocator);
    self.chunk_map.deinit(self.allocator);

}



fn enabledChunk(self: *World, position: Vec3i) !*Chunk {
    const id = try self.chunk_id_pool.acquire(self.allocator);
    if (id >= self.chunks.len) {
        std.debug.assert(id == self.chunks.len);
        const chunk = try self.chunk_arena.allocator().create(Chunk);
        chunk.id = id;
        try self.chunks.append(self.allocator, chunk);
    }
    const chunk = self.chunks.items[id];
    chunk.position = position;
    chunk.state = .loading;
    try self.chunk_map.put(self.allocator, position, chunk);
    return chunk;
}

fn disableChunk(self: *World, id: Chunk.Id) void {
    const chunk = self.chunks.items[id];
    chunk.state = .disabled;
    self.chunk_map.remove(chunk.position);
    self.chunk_id_pool.release(id);
}

pub const ChunkMap = std.HashMapUnmanaged(Vec3i, Chunk.Id, struct {
    pub fn hash(_: @This(), x: Vec3i) u64 {
        var h: u64 = @bitCast(u32, x.v[0]);
        h = (h << 16) ^ @bitCast(u32, x.v[1]);
        h = (h << 16) ^ @bitCast(u32, x.v[2]);
        return h;
    }
    pub fn eql(_ :@This(), a: Vec3i, b: Vec3i) bool {
        return a.eql(b);
    }
}, std.hash_map.default_max_load_percentage);

pub const Chunk = struct {
    id: Id,
    position:  Vec3i,
    state: State,

    pub const Id = usize;

    pub const IdPool = util.IdPoolUnmanaged(Id);

    pub const width_bits = 5;
    pub const width = 1 << width_bits;

    pub const State = enum {
        disabled,
        loading,
        active,
        cancelled,
        unloading,
    };
};

pub fn ChunkData(comptime T: type) type {
    return struct {
        const Self = @This();

        data: List(T) = .{},

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.data.deinit(allocator);
        }

        /// make sure allocated data count is the same as world chunk count
        /// if no allocation is needed, returns null
        /// if allocation occurs, returns slice to the new items so they can be initialized
        pub fn update(self: *Self, allocator: Allocator, world: World) !?[]T {
            std.debug.assert(self.data.items.len <= world.chunks.items.len);
            if (self.data.items.len < world.chunks.items.len) {
                const old_len = self.data.items.len;
                try self.data.resize(allocator, world.chunks.items.len);
                return self.data.items[old_len..];
            }
            else {
                return null;
            }
        }
    };
}

pub const Observer = struct {
    /// position in world coordinates of the observer
    /// write to this whenever the observer moves, changes will be detected
    /// during the next tick
    world_position: Vec3,
    /// the last recorded load center, ie the position of the center chunk
    load_center: ?Vec3i = null,
    /// index in observer list
    /// makes removal O(1)
    index: usize,

    ctx: *anyopaque,
    get_position_fn: *const fn(*anyopaque) Vec3,
    mutex: Mutex = .{},


    fn GetPositionFn(comptime Ptr: type) type {
        return fn(Ptr) Vec3;
    }

    fn init(
        ptr: anytype,
        comptime get_position_fn: GetPositionFn(@TypeOf(ptr))
    ) Observer {
        const Ptr = @TypeOf(ptr);
        const info = @typeInfo(Ptr).Pointer;
        const S = struct {
            fn getPosition(p: *anyopaque) Vec3 {
                return get_position_fn(
                    @ptrCast(Ptr, @alignCast(info.alignment, p))
                );
            }
        };
        return Observer {
            .world_position = undefined,
            .index = undefined,
            .ctx = @ptrCast(*anyopaque, ptr),
            .get_position_fn = &S.getPosition,
        };
    }

    fn setLoadCenterFromWorldPosition(self: *Observer) void {
        self.load_center = self.world_position.divScalar(@intToFloat(f32, Chunk.width)).round().cast(i32);
        std.log.debug("observer load center {d}", .{self.load_center.?});
    }
};

const Thread = std.Thread;
const AtomicBool = std.atomic.Atomic(bool);

pub const Manager = struct {

    allocator: Allocator,
    world: *World,
    thread: Thread = undefined,
    is_running: AtomicBool = AtomicBool.init(false),

    pending_chunks: List(Chunk.Id) = .{},

    observers: List(*Observer) = .{},
    observer_mutex: Mutex = .{},
    observer_events: ObserverEvents,

    const ObserverEvents = util.Events(union (enum) {
        add: *Observer,
        remove: *const usize,
    });

    pub fn create(allocator: Allocator, world: *World) !*Manager {
        const self = try allocator.create(Manager);
        self.* = .{
            .allocator = allocator,
            .world = world,
            .observer_events = ObserverEvents.init(allocator),
        };
        return self;
    }

    pub fn destroy(self: *Manager) void {
        self.stop();
        const allocator = self.allocator;
        defer allocator.destroy(self);
        self.pending_chunks.deinit(allocator);
        for (self.observer_events.get(.add)) |observer| {
            allocator.destroy(observer);
        }
        self.observer_events.deinit();
        for (self.observers.items) |observer| {
            allocator.destroy(observer);
        }
        self.observers.deinit(self.allocator);

    }

    pub fn isRunning(self: Manager) bool {
        return self.is_running.load(.Monotonic);
    }

    pub fn HookFunction(comptime HookCtx: type) type {
        return fn (HookCtx, *const World) anyerror!void;
    }

    pub fn start(self: *Manager) !void {
        try self.startWithHook(void{}, (struct {
            fn f(_: void, _: *const World) !void {}
        }).f);
    }

    pub fn startWithHook(
        self: *Manager,
        ctx: anytype,
        comptime hook_fn: HookFunction(@TypeOf(ctx))
    ) !void {
        if (!self.isRunning()) {
            self.is_running.store(true, .Monotonic);
            const S = struct {
                fn tMain(s: *Manager, c: @TypeOf(ctx)) !void {
                    try s.threadMain(c, hook_fn);
                }
            };
            self.thread = try Thread.spawn(.{}, S.tMain, .{self, ctx});
        }
    }

    pub fn stop(self: *Manager) void {
        if (self.isRunning()) {
            self.is_running.store(false, .Monotonic);
            self.thread.join();
        }
    }

    fn threadMain(
        self: *Manager,
        ctx: anytype,
        comptime hook_fn: HookFunction(@TypeOf(ctx))
    ) !void {
        while (self.isRunning()) {
            try self.updateObserverList();
            for (self.observers.items) |observer| {
                if (observer.load_center) |load_center| {
                    const load_center_pos = load_center.mulScalar(Chunk.width).cast(f32);
                    if (load_center_pos.sub(observer.world_position).mag2() > @intToFloat(f32, Chunk.width * Chunk.width)) {
                        observer.setLoadCenterFromWorldPosition();
                    }
                }
                else {
                    observer.setLoadCenterFromWorldPosition();
                }
            }
            // call user hook
            try hook_fn(ctx, self.world);

        }
    }

    pub fn addObserver(
        self: *Manager,
        ptr: anytype,
        comptime get_position_fn: Observer.GetPositionFn(@TypeOf(ptr))
    ) !*const Observer {
        self.observer_mutex.lock();
        defer self.observer_mutex.unlock();
        const observer = try self.allocator.create(Observer);
        observer.* = Observer.init(ptr, get_position_fn);
        observer.world_position = get_position_fn(ptr);
        try self.observer_events.post(.add, observer);
        return observer;
    }

    pub fn removeObserver(self: *Manager, observer: *const Observer) !void {
        self.observer_mutex.lock();
        defer self.observer_mutex.unlock();
        try self.observer_events.post(.remove, &observer.index);
    }

    fn updateObserverList(self: *Manager) !void {
        self.observer_mutex.lock();
        defer self.observer_mutex.unlock();
        for (self.observer_events.get(.add)) |observer| {
            observer.index = self.observers.items.len;
            try self.observers.append(self.allocator, observer);
        }
        for (self.observer_events.get(.remove)) |index| {
            const observer = self.observers.items[index.*];
            if (self.observers.items.len > 1) {
                const last = self.observers.items[self.observers.items.len - 1];
                last.index = observer.index;
                self.observers.items[observer.index] = last;
            }
            self.observers.items.len -= 1;
            self.allocator.destroy(observer);
        }
        self.observer_events.clearAll();
    }


    pub fn tick(self: *Manager) void {
        self.updateObserverPositions();
    }

    fn updateObserverPositions(self: *Manager) void {
        self.observer_mutex.lock();
        defer self.observer_mutex.unlock();
        for (self.observers.items) |observer| {
            observer.mutex.lock();
            defer observer.mutex.unlock();
            observer.world_position = observer.get_position_fn(observer.ctx);
        }
    }

};