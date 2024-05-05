const std = @import("std");
const ziglua = @import("ziglua");

const Allocator = std.mem.Allocator;
const Lua = ziglua.Lua;
const Dir = std.fs.Dir;

const Mun = @This();

allocator: Allocator,
lua: *Lua,

pub fn create(allocator: Allocator, data_dir_path: []const u8) !*Mun {
    const self = try allocator.create(Mun);
    errdefer allocator.destroy(self);
    self.allocator = allocator;
    self.lua = try Lua.init(&self.allocator);
    errdefer self.lua.deinit();
    try self.loadLuaLibs(data_dir_path);
    return self;
}

pub fn destroy(self: *Mun) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.lua.deinit();
}

fn loadLuaLibs(self: *Mun, data_dir_path: []const u8) !void {
    self.lua.openBase();
    self.lua.openPackage();
    self.lua.openString();
    self.lua.openUtf8();
    self.lua.openTable();
    self.lua.openMath();
    _ = try self.lua.getGlobal("package");

    const require_path = try std.fs.path.joinZ(self.allocator, &.{ data_dir_path, "mun", "?.lua" });
    defer self.allocator.free(require_path);

    _ = self.lua.pushStringZ(require_path);
    self.lua.setField(-2, "path");
    self.lua.pop(2);
}

pub fn requireModule(self: *Mun, module_name: []const u8) !void {
    const source = try std.fmt.allocPrintZ(self.allocator, "require \"{s}\"", .{module_name});
    defer self.allocator.free(source);
    try self.lua.doString(source);
}
