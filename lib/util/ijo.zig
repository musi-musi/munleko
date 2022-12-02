const std = @import("std");
const idpool = @import("idpool.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const IjoId = u32;
pub const IjoIdPool = idpool.IdPoolUnmanaged(IjoId);

pub fn Ijo(comptime ijo_type_name_: []const u8) type {
    return struct {
        id: IjoId,

        pub const ijo_type_name = ijo_type_name_;
    };
}

pub fn isIjoType(comptime T: type) bool {
    comptime {
        return @hasDecl(T, "ijo_type_name") and T == Ijo(T.ijo_type_name);
    }
}

pub fn assertIsIjoType(comptime T: type) void {
    comptime {
        if (!isIjoType(T)) {
            @compileError(@typeName(T) ++ " is not an Ijo type");
        }
    }
}

pub fn IjoPool(comptime IjoType_: type) type {
    assertIsIjoType(IjoType_);
    return struct {
        allocator: Allocator,
        id_pool: IjoIdPool,

        pub const IjoType = IjoType_;

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self {
                .allocator = allocator,
                .id_pool = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.id_pool.deinit(self.allocator);
        }

        pub fn create(self: *Self) !IjoType {
            const id = try self.id_pool.acquire(self.allocator);
            return .{
                .id = id,
            };
        }

        pub fn destroy(self: *Self, ijo: IjoType) void {
            self.id_pool.release(ijo.id);
        }
    };
}

pub fn IjoDataStoreDefaultInit(comptime IjoType: type, comptime Data: type) type {
    return IjoDataStoreValueInit(IjoType, Data, Data{});
}

pub fn IjoDataStoreValueInit(comptime IjoType: type, comptime Data: type, comptime init_value: Data) type {
    return IjoDataStore(IjoType, Data, struct {
        fn initData(_: @This(), _: *ArenaAllocator) !Data {
            return init_value;
        }
    });
}

pub fn IjoDataStore(comptime IjoType_: type, comptime Data_: type, comptime Context_: type) type {
    assertIsIjoType(IjoType_);

    return struct {

        allocator: Allocator,
        arena: ArenaAllocator,
        context: Context,
        segments: std.ArrayListUnmanaged(*Segment) = .{},
        capacity: usize = 0,

        pub const IjoType = IjoType_;
        pub const Data = Data_;
        pub const Segment = [segment_len]Data;
        pub const Context = Context_;
        
        pub const segment_len_bits = 8;
        pub const segment_len = 1 << segment_len_bits;

        const Self = @This();

        pub fn initWithContext(allocator: Allocator, context: Context) Self {
            return Self {
                .allocator = allocator,
                .arena = ArenaAllocator.init(allocator),
                .context = context,
            };
        }

        pub fn init(allocator: Allocator) Self {
            return initWithContext(allocator, .{});
        }

        pub fn deinit(self: *Self) void {
            if (@hasDecl(Context, "deinitValue")) {
                var i: usize = 0;
                while (i < self.capacity) : (i += 1) {
                    self.context.deinitValue(self.ptrFromIndex(i));
                }
            }
            self.arena.deinit();
            self.segments.deinit(self.allocator);
        }

        pub fn get(self: Self, ijo: IjoType) Data {
            return self.ptrFromIndex(ijo.id).*;
        }

        pub fn getPtr(self: *Self, ijo: IjoType) *Data {
            return self.ptrFromIndex(ijo.id);
        }

        fn ptrFromIndex(self: Self, index: usize) *Data {
            return &self.segments.items[@divFloor(index, segment_len)].*[index % segment_len];
        }

        pub fn matchCapacity(self: *Self, pool: IjoPool(IjoType)) !void {
            if (self.capacity < pool.capacity) {
                const new_segment_count = std.math.divCeil(usize, pool.capacity, segment_len);
                const old_segment_count = self.segments.items.len;
                if (old_segment_count > new_segment_count) {
                    try self.segments.resize(self.allocator, new_segment_count);
                    for (self.segments.items[old_segment_count..new_segment_count]) |*segment| {
                        segment.* = try self.arena.allocator().create(Segment);
                    }
                }
                var i: usize = self.capacity;
                while (i < pool.capacity) : (i += 1) {
                    self.ptrFromIndex(i).* = try self.context.initData(self.arena);
                }
                self.capacity = pool.capacity;
            }
        }
    };
}