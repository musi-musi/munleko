const std = @import("std");
// const oko = @import("oko");
const idpool = @import("idpool.zig");

const Events = @import("event.zig").Events;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const IjoId = u32;
pub const IjoIdPool = idpool.IdPoolUnmanaged(IjoId);

pub fn Ijo(comptime ijo_type_name_: []const u8) type {
    return enum(IjoId) {
        _,
        pub const ijo_type_name = ijo_type_name_;

        const Self = @This();

        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("[{s} {d}]", .{ ijo_type_name, @intFromEnum(self) });
        }

        pub const HashContext = struct {
            pub fn hash(_: HashContext, x: Self) u64 {
                return @intFromEnum(x);
            }
            pub fn eql(_: HashContext, a: Self, b: Self) bool {
                return a == b;
            }
        };
    };
}

pub fn isIjo(comptime T: type) bool {
    comptime {
        return @hasDecl(T, "ijo_type_name") and T == Ijo(T.ijo_type_name);
    }
}

pub fn assertIsIjo(comptime T: type) void {
    comptime {
        if (!isIjo(T)) {
            @compileError(@typeName(T) ++ " is not an Ijo type");
        }
    }
}

pub fn IjoPool(comptime IjoT_: type) type {
    assertIsIjo(IjoT_);
    return struct {
        allocator: Allocator,
        id_pool: IjoIdPool,

        pub const IjoT = IjoT_;

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .id_pool = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.id_pool.deinit(self.allocator);
        }

        pub fn create(self: *Self) !IjoT {
            const id = try self.id_pool.acquire(self.allocator);
            return @as(IjoT, @enumFromInt(id));
        }

        pub fn delete(self: *Self, ijo: IjoT) void {
            self.id_pool.release(@intFromEnum(ijo));
        }

        pub fn capacity(self: Self) usize {
            return self.id_pool.capacity;
        }
    };
}

pub fn IjoDataStoreDefaultInit(comptime IjoT: type, comptime Data: type) type {
    return IjoDataStoreValueInit(IjoT, Data, Data{});
}

pub fn IjoDataStoreValueInit(comptime IjoT: type, comptime Data: type, comptime init_value: Data) type {
    return IjoDataStore(IjoT, Data, struct {
        fn initData(_: @This(), _: *ArenaAllocator) !Data {
            return init_value;
        }
    });
}

pub fn IjoDataStoreArenaInit(comptime IjoT: type, comptime Data: type) type {
    return IjoDataStore(IjoT, *Data, struct {
        fn initData(_: @This(), arena: *ArenaAllocator) !*Data {
            return arena.allocator().create(Data);
        }
    });
}

pub fn IjoEventsStore(comptime IjoT: type, comptime channels_def: type) type {
    const EventsT = Events(channels_def);
    return IjoDataStore(IjoT, *EventsT, struct {
        fn initData(_: @This(), arena: *ArenaAllocator) !*EventsT {
            const events = try arena.allocator().create(EventsT);
            events.* = EventsT.init(arena.child_allocator);
            return events;
        }
        fn deinitData(_: @This(), events: **EventsT) void {
            events.*.deinit();
        }
    });
}

pub fn IjoDataListStore(comptime IjoT: type, comptime T: type) type {
    const ListT = std.ArrayList(T);
    return IjoDataStore(IjoT, *ListT, struct {
        fn initData(_: @This(), arena: *ArenaAllocator) !*ListT {
            const list = try arena.allocator().create(ListT);
            list.* = ListT.init(arena.child_allocator);
            return list;
        }

        fn deinitData(_: @This(), list: **ListT) void {
            list.*.deinit();
        }
    });
}

// completely thread safe as long as capacity is always updated before being written to
pub fn IjoDataStore(comptime IjoT_: type, comptime Data_: type, comptime Context_: type) type {
    assertIsIjo(IjoT_);

    return struct {
        allocator: Allocator,
        arena: ArenaAllocator,
        context: Context,
        segments: [segment_count]*Segment = undefined,
        capacity: usize = 0,

        pub const IjoT = IjoT_;
        pub const Data = Data_;
        pub const Segment = [segment_len]Data;
        pub const Context = Context_;

        pub const segment_count_bits = 10;
        pub const segment_count = 1 << segment_count_bits;

        pub const segment_len_bits = 10;
        pub const segment_len = 1 << segment_len_bits;

        pub const max_capacity = segment_count * segment_len;

        const Self = @This();

        pub fn initWithContext(allocator: Allocator, context: Context) Self {
            // const oko_trace = comptime std.fmt.comptimePrint("{s} {s}", .{IjoT_.ijo_type_name, @typeName(Data)});
            // const alloc = oko.wrapAllocator(oko_trace, allocator);
            const alloc = allocator;
            return Self{
                .allocator = alloc,
                .arena = ArenaAllocator.init(alloc),
                .context = context,
            };
        }

        pub fn init(allocator: Allocator) Self {
            return initWithContext(allocator, .{});
        }

        pub fn deinit(self: *Self) void {
            if (@hasDecl(Context, "deinitData")) {
                var i: usize = 0;
                while (i < self.capacity) : (i += 1) {
                    self.context.deinitData(self.ptrFromIndex(i));
                }
            }
            self.arena.deinit();
        }

        pub fn get(self: Self, ijo: IjoT) Data {
            return self.ptrFromIndex(@intFromEnum(ijo)).*;
        }

        pub fn getPtr(self: *Self, ijo: IjoT) *Data {
            return self.ptrFromIndex(@intFromEnum(ijo));
        }

        fn ptrFromIndex(self: Self, index: usize) *Data {
            return &self.segments[@divFloor(index, segment_len)].*[index % segment_len];
        }

        pub fn matchCapacity(self: *Self, pool: IjoPool(IjoT)) !void {
            const new_capacity = pool.capacity();
            if (self.capacity < new_capacity) {
                const new_segment_count = std.math.divCeil(usize, new_capacity, segment_len) catch unreachable;
                const old_segment_count = std.math.divCeil(usize, self.capacity, segment_len) catch unreachable;
                if (old_segment_count < new_segment_count) {
                    for (self.segments[old_segment_count..new_segment_count]) |*segment| {
                        segment.* = try self.arena.allocator().create(Segment);
                    }
                }
                var i: usize = self.capacity;
                while (i < new_capacity) : (i += 1) {
                    self.ptrFromIndex(i).* = try self.context.initData(&self.arena);
                }
                self.capacity = new_capacity;
            }
        }
    };
}
