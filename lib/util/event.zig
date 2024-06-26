const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn Events(comptime channels_def: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        channels: Channels = .{},

        const Unmanaged = EventsUnmanaged(channels_def);

        pub const channel_tags = Unmanaged.channel_tags;
        pub const ChannelTag = Unmanaged.ChannelTag;
        pub const Channels = Unmanaged.Channels;
        pub const Event = Unmanaged.Event;

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            inline for (channel_tags) |tag| {
                @field(self.channels, @tagName(tag)).deinit(self.allocator);
            }
        }

        pub fn clearAll(self: *Self) void {
            inline for (channel_tags) |tag| {
                @field(self.channels, @tagName(tag)).clearRetainingCapacity();
            }
        }

        pub fn clear(self: *Self, comptime tag: ChannelTag) void {
            @field(self.channels, @tagName(tag)).clearRetainingCapacity();
        }

        pub fn post(self: *Self, comptime tag: ChannelTag, event: Event(tag)) !void {
            try @field(self.channels, @tagName(tag)).append(self.allocator, event);
        }

        pub fn get(self: Self, comptime tag: ChannelTag) []const Event(tag) {
            return @field(self.channels, @tagName(tag)).items;
        }
    };
}

pub fn EventsUnmanaged(comptime channels_def: type) type {
    return struct {
        channels: Channels = .{},

        pub const channel_tags = std.enums.values(ChannelTag);

        pub const ChannelTag = std.meta.Tag(channels_def);
        pub const Channels = blk: {
            const fields = std.meta.fields(channels_def);
            var channels_fields: [fields.len]std.builtin.Type.StructField = undefined;
            for (fields, 0..) |field, i| {
                const List = std.ArrayListUnmanaged(field.type);
                const default_value: List = .{};
                channels_fields[i] = .{
                    .name = field.name,
                    .type = List,
                    .default_value = &default_value,
                    .is_comptime = false,
                    .alignment = @alignOf(List),
                };
            }
            break :blk @Type(.{
                .Struct = .{
                    .layout = .auto,
                    .fields = &channels_fields,
                    .decls = &.{},
                    .is_tuple = false,
                },
            });
        };

        pub fn Event(comptime tag: ChannelTag) type {
            const fields = std.meta.fields(channels_def);
            for (fields) |field| {
                if (std.mem.eql(u8, field.name, @tagName(tag))) {
                    return field.type;
                }
            }
            unreachable;
        }

        const Self = @This();

        pub fn deinit(self: *Self, allocator: Allocator) void {
            inline for (channel_tags) |tag| {
                @field(self.channels, @tagName(tag)).deinit(allocator);
            }
        }

        pub fn clearAll(self: *Self) void {
            inline for (channel_tags) |tag| {
                @field(self.channels, @tagName(tag)).clearRetainingCapacity();
            }
        }

        pub fn clear(self: *Self, comptime tag: ChannelTag) void {
            @field(self.channels, @tagName(tag)).clearRetainingCapacity();
        }

        pub fn post(self: *Self, allocator: Allocator, comptime tag: ChannelTag, event: Event(tag)) !void {
            try @field(self.channels, @tagName(tag)).append(allocator, event);
        }

        pub fn get(self: Self, comptime tag: ChannelTag) []const Event(tag) {
            return @field(self.channels, @tagName(tag)).items;
        }
    };
}

test "post and get" {
    const E = Events(union(enum) {
        a: u8,
        b: []const u8,
        c: f32,
    });

    var e = E.init(std.testing.allocator);
    defer e.deinit();

    try e.post(.a, 'a');
    try e.post(.a, 'b');
    try e.post(.a, 'c');
    try e.post(.a, 'd');

    try e.post(.b, "hello");
    try e.post(.b, "world");

    try e.post(.c, 3.14);

    try std.testing.expectEqualSlices(u8, &[_]u8{ 'a', 'b', 'c', 'd' }, e.get(.a));
    try std.testing.expectEqualStrings("hello", e.get(.b)[0]);
    try std.testing.expectEqualStrings("world", e.get(.b)[1]);
    try std.testing.expectEqualSlices(f32, &[_]f32{3.14}, e.get(.c));

    e.clearAll();

    try std.testing.expectEqual(@as(usize, 0), e.get(.a).len);
    try std.testing.expectEqual(@as(usize, 0), e.get(.b).len);
    try std.testing.expectEqual(@as(usize, 0), e.get(.c).len);
}
