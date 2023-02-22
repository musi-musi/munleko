const std = @import("std");
const ziglua = @import("ziglua");
const mun = @import("mun");
const nm = @import("nm");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const Lua = ziglua.Lua;

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;

const AssetDatabase = @This();


allocator: Allocator,

leko_table: LekoAssetTable = undefined,

pub fn create(allocator: Allocator) !*AssetDatabase {
    const self = try allocator.create(AssetDatabase);
    self.* = .{
        .allocator = allocator,
    };
    self.leko_table.init(allocator);
    return self;
}

pub fn destroy(self: *AssetDatabase) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.leko_table.deinit();
}


pub fn AssetTable(comptime Asset_: type) type {
    return struct {
        map: AssetMap,
        name_arena: Arena,

        pub const Asset = Asset_;
        pub const AssetMap = std.StringHashMap(Asset);

        const Self = @This();

        pub fn init(self: *Self, allocator: Allocator) void {
            self.map = AssetMap.init(allocator);
            self.name_arena = Arena.init(allocator);
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
            self.name_arena.deinit();
        }

        pub fn addAsset(self: *Self, name: []const u8, asset: Asset) !void {
            const owned_name = try self.name_arena.allocator().dupe(u8, name);
            try self.map.put(owned_name, asset);
        }

        pub fn getByName(self: Self, name: []const u8) ?Asset {
            return self.map.get(name);
        }

        pub const LuaAssetLoader = fn(*Lua, []const u8) anyerror!?Asset;

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
            lua.pushNil();
            var error_count: usize = 0;
            while (lua.next(-2)) {
                const key_type = lua.typeOf(-2);
                if (key_type != .string) {
                    std.log.err("asset name in {s} table is of type {s}. only string names are allowed", .{table_name, @tagName(key_type)});
                    error_count += 1;
                    lua.pop(1);
                    continue;
                }
                const name = try lua.toBytes(-2);
                if (try loader(lua, name)) |asset| {
                    try self.addAsset(name, asset);
                    std.log.info("loaded {s} asset '{s}'", .{table_name, name});
                }
                else {
                    error_count += 1;
                }
                lua.pop(1);
            }
            return error_count;
        }

    };
}

pub fn load(self: *AssetDatabase, lua: *Lua) !void {
    var error_count: usize = 0;
    lua.getGlobal("assets") catch {
        std.log.err("missing 'assets' table in global lua state", .{});
        return error.LuaAssetTableMissing;
    };
    error_count += try self.leko_table.addAssetsFromLuaAssetTable(lua, "leko", loadLekoLuaAsset);
    lua.pop(1);
    std.log.info("loaded assets ({d} errors)", .{error_count});
}

pub const LekoAsset = struct {
    is_solid: bool = true,
    is_visible: bool = true,
    color: Vec3 = undefined,
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
        asset.is_solid = l.toBoolean(-1);
    }
    l.pop(1);
    if (l.getField(-1, "color") == .nil) {
        std.log.err("leko asset {s} is missing field 'color'", .{name});
        l.pop(1);
        return null;
    }
    if (mun.toVec3(l, -1)) |color| {
        asset.color = vec3(color);
    }
    else |_| {
        std.log.err("leko asset {s} 'color' field could not be read", .{name});
        l.pop(1);
        return null;
    }
    l.pop(1);
    return asset;
}