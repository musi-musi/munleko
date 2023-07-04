const std = @import("std");
const ziglua = @import("ziglua");
const mun = @import("mun");
const nm = @import("nm");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const Lua = ziglua.Lua;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;

const Assets = @This();

const stb_image = @cImport(@cInclude("stb_image.h"));

const leko = @import("leko.zig");
const LekoTypeTable = leko.LekoTypeTable;

allocator: Allocator,

leko_table: LekoAssetTable = undefined,
leko_texture_table: LekoTextureAssetTable = undefined,

leko_texture_size: usize = undefined,

leko_type_table: LekoTypeTable,

pub fn create(allocator: Allocator) !*Assets {
    const self = try allocator.create(Assets);
    self.* = .{
        .allocator = allocator,
        .leko_type_table = undefined,
    };
    self.leko_table.init(allocator);
    self.leko_texture_table.init(allocator);
    try self.leko_type_table.init(allocator);
    return self;
}

pub fn destroy(self: *Assets) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.leko_table.deinit();
    self.leko_texture_table.deinit();
    self.leko_type_table.deinit();
}

pub const ImageData = struct {
    width: usize,
    height: usize,
    pixels: [][4]u8,
};

pub fn decodePng(allocator: Allocator, data: []const u8) !ImageData {
    const len = @as(c_int, @intCast(data.len));
    var width: c_int = undefined;
    var height: c_int = undefined;
    if (stb_image.stbi_load_from_memory(data.ptr, len, &width, &height, null, 4)) |bytes| {
        defer stb_image.stbi_image_free(bytes);
        const w = @as(usize, @intCast(width));
        const h = @as(usize, @intCast(height));
        const pixels = @as([*][4]u8, @ptrCast(bytes))[0 .. w * h];
        return ImageData{
            .width = w,
            .height = h,
            .pixels = try allocator.dupe([4]u8, pixels),
        };
    }
    return error.BadPng;
}

pub fn AssetTable(comptime Asset_: type) type {
    return struct {
        map: AssetMap,
        arena: Arena,

        pub const Asset = Asset_;
        pub const AssetMap = std.StringHashMap(Asset);

        const Self = @This();

        pub fn init(self: *Self, allocator: Allocator) void {
            self.map = AssetMap.init(allocator);
            self.arena = Arena.init(allocator);
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
            self.arena.deinit();
        }

        pub fn addAsset(self: *Self, name: []const u8, asset: Asset) !void {
            const owned_name = try self.arena.allocator().dupe(u8, name);
            try self.map.put(owned_name, asset);
        }

        pub fn getByName(self: Self, name: []const u8) ?Asset {
            return self.map.get(name);
        }

        pub const LuaAssetLoader = fn (*Lua, []const u8) anyerror!?Asset;

        /// add assets from the assets table loaded by lua
        /// the `asset` table provided by main.lua must be on the top of the stack
        /// iterates over the keys of `assets[table_name]` and calls `loader` to decode the lua values provided on the top of the stack
        /// return the number of errors encountered
        pub fn addAssetsFromLuaAssetTable(self: *Self, lua: *Lua, table_name: [:0]const u8, comptime loader: LuaAssetLoader) !usize {
            if (lua.getField(-1, table_name) == .nil) {
                std.log.err("lua assets missing asset table '{s}'", .{table_name});
                lua.pop(1);
                return 1;
            }
            defer lua.pop(1);
            lua.pushNil();
            // defer lua.pop(1);
            var error_count: usize = 0;
            while (lua.next(-2)) {
                const key_type = lua.typeOf(-2);
                if (key_type != .string) {
                    std.log.err("asset name in {s} table is of type {s}. only string names are allowed", .{ table_name, @tagName(key_type) });
                    error_count += 1;
                    lua.pop(1);
                    continue;
                }
                const name = try lua.toBytes(-2);
                if (try loader(lua, name)) |asset| {
                    try self.addAsset(name, asset);
                    // std.log.info("loaded {s} asset '{s}'", .{table_name, name});
                } else {
                    error_count += 1;
                }
                lua.pop(1);
            }
            return error_count;
        }
    };
}

pub fn load(self: *Assets, lua: *Lua, data_root_path: []const u8) !void {
    var data_dir = try std.fs.openDirAbsolute(data_root_path, .{});
    defer data_dir.close();
    var error_count: usize = 0;
    _ = lua.getGlobal("assets") catch {
        std.log.err("missing 'assets' table in global lua state", .{});
        return error.LuaAssetTableMissing;
    };
    defer lua.pop(1);
    error_count += try self.leko_table.addAssetsFromLuaAssetTable(lua, "leko", loadLekoLuaAsset);

    if (lua.getField(-1, "leko_texture_size") == .nil) {
        std.log.err("assets table missing field 'leko_texture_size'", .{});
        return error.MissingLekoTextureSize;
    }
    if (lua.toInteger(-1)) |texture_size| {
        self.leko_texture_size = @as(usize, @intCast(texture_size));
    } else |_| {
        std.log.err("assets table field 'leko_texture_size' is not an be integer number", .{});
    }
    lua.pop(1);
    var texture_dir = try data_dir.openDir("textures", .{});
    defer texture_dir.close();
    error_count += try self.loadLekoTextures(texture_dir);
    std.log.info("loaded assets ({d} errors)", .{error_count});

    try self.leko_type_table.addLekoTypesFromAssetTable(self.leko_table);
}

pub const LekoAsset = struct {
    is_solid: bool = true,
    is_visible: bool = true,
    color: Vec3 = Vec3.one,
    texture_name: []const u8 = undefined,
};

pub const LekoAssetTable = AssetTable(LekoAsset);

fn loadLekoLuaAsset(l: *Lua, name: []const u8) !?LekoAsset {
    if (std.mem.eql(u8, name, "empty")) {
        std.log.err("leko asset '{s}' uses reserved name", .{name});
        return null;
    }
    var asset: LekoAsset = .{};
    if (l.getField(-1, "is_solid") != .nil) {
        asset.is_solid = l.toBoolean(-1);
    }
    l.pop(1);
    if (l.getField(-1, "is_visible") != .nil) {
        asset.is_visible = l.toBoolean(-1);
    }
    l.pop(1);
    if (l.getField(-1, "color") != .nil) {
        if (mun.toVec3(l, -1)) |color| {
            asset.color = vec3(color);
        } else |_| {
            std.log.err("leko asset {s} 'color' field could not be read", .{name});
            l.pop(1);
            return null;
        }
    }
    l.pop(1);
    switch (l.getField(-1, "texture")) {
        .nil => asset.texture_name = name,
        .string => asset.texture_name = try l.toBytes(-1),
        else => |t| {
            std.log.err("leko asset {s} 'texture' field must be string, not {s}", .{ name, @tagName(t) });
            l.pop(1);
            return null;
        },
    }
    l.pop(1);
    return asset;
}

pub const LekoTextureAsset = struct {
    index: usize,
    pixels: [][4]u8,
};

pub const LekoTextureAssetTable = AssetTable(LekoTextureAsset);

fn loadLekoTextures(self: *Assets, texture_dir: std.fs.Dir) !usize {
    var file_name_buffer: [1024]u8 = undefined;
    const texture_size = self.leko_texture_size;

    var leko_textures_dir = try texture_dir.openDir("leko", .{});
    defer leko_textures_dir.close();

    // add missing texture
    try self.leko_texture_table.addAsset("", .{
        .index = 0,
        .pixels = blk: {
            const pixels = try self.leko_texture_table.arena.allocator().alloc([4]u8, texture_size * texture_size);
            @memset(pixels, [4]u8{ 255, 0, 255, 255 });
            break :blk pixels;
        },
    });

    var error_count: usize = 0;
    var leko_iter = self.leko_table.map.valueIterator();
    while (leko_iter.next()) |leko_asset| {
        const name = leko_asset.texture_name;
        if (self.leko_texture_table.getByName(name) != null) {
            continue;
        }
        const file_name = try std.fmt.bufPrint(&file_name_buffer, "{s}.png", .{name});
        var file = leko_textures_dir.openFile(file_name, .{}) catch |e| {
            std.log.err("error opening leko texture file '{s}': {s}", .{ file_name, @errorName(e) });
            error_count += 1;
            continue;
        };
        defer file.close();
        const file_bytes = try file.readToEndAlloc(self.allocator, 1 << 32);
        defer self.allocator.free(file_bytes);

        const texture_data = decodePng(self.leko_texture_table.arena.allocator(), file_bytes) catch {
            std.log.err("error decoding leko texture '{s}'", .{file_name});
            error_count += 1;
            continue;
        };
        if (texture_data.width != texture_size or texture_data.height != texture_size) {
            std.log.err("leko texture '{s}' is incorrect size {d}x{d}, should be {d}x{d}", .{
                file_name,
                texture_data.width,
                texture_data.height,
                texture_size,
                texture_size,
            });
            error_count += 1;
            continue;
        }
        const texture_asset = LekoTextureAsset{
            .index = self.leko_texture_table.map.count(),
            .pixels = texture_data.pixels,
        };
        try self.leko_texture_table.addAsset(name, texture_asset);
    }

    return error_count;
}
