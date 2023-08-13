const std = @import("std");
const ziglua = @import("ziglua");
const mun = @import("mun");
const nm = @import("nm");

pub const Session = @import("engine/Session.zig");
pub const Assets = @import("engine/Assets.zig");
pub const World = @import("engine/World.zig");
pub const Player = @import("engine/Player.zig");
pub const leko = @import("engine/leko.zig");
pub const Save = @import("engine/Save.zig");

const Allocator = std.mem.Allocator;

const Lua = ziglua.Lua;

const Dir = std.fs.Dir;

allocator: Allocator,
arguments: Arguments,
data_dir: Dir,
data_dir_path: []const u8,
saves_root_path: []const u8,

lua: Lua,
assets: *Assets,

const Engine = @This();

pub fn create(allocator: Allocator, arguments: Arguments) !*Engine {
    const self = try allocator.create(Engine);
    errdefer allocator.destroy(self);
    self.* = Engine{
        .allocator = allocator,
        .arguments = arguments,
        .data_dir = undefined,
        .data_dir_path = undefined,
        .saves_root_path = undefined,
        .lua = try Lua.init(allocator),
        .assets = try Assets.create(allocator),
    };
    errdefer self.assets.destroy();
    errdefer self.lua.deinit();
    const data_dir_path = try getDataRoot(allocator, arguments.data_dir_path);
    self.data_dir_path = data_dir_path;
    errdefer allocator.free(data_dir_path);
    const saves_root_path = try std.fs.path.resolve(allocator, &.{ data_dir_path, "saves" });
    errdefer allocator.free(saves_root_path);
    self.data_dir = try std.fs.openDirAbsolute(data_dir_path, .{});
    errdefer self.data_dir.close();
    if (std.fs.makeDirAbsolute(saves_root_path)) {} else |err| {
        if (err != std.os.MakeDirError.PathAlreadyExists) {
            return err;
        }
    }
    self.saves_root_path = saves_root_path;
    try self.initLua();
    return self;
}

fn getDataRoot(allocator: Allocator, arg_data_root_path: ?[]const u8) ![]const u8 {
    if (arg_data_root_path) |data_dir_path| {
        const cwd = std.fs.cwd();
        return cwd.realpathAlloc(allocator, data_dir_path);
    } else {
        const exe_dir_path = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(exe_dir_path);
        return std.fs.path.resolve(allocator, &.{ exe_dir_path, "data" });
    }
}

pub fn destroy(self: *Engine) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.data_dir.close();
    allocator.free(self.data_dir_path);
    allocator.free(self.saves_root_path);
    self.lua.deinit();
    self.assets.destroy();
}

pub fn load(self: *Engine) !void {
    const l = &self.lua;
    const lua_main_path = try std.fs.path.joinZ(self.allocator, &.{ self.data_dir_path, "main.lua" });
    defer self.allocator.free(lua_main_path);
    try l.doFile(lua_main_path);
    try self.assets.load(l, self.data_dir);
}

fn initLua(self: *Engine) !void {
    const l = &self.lua;
    l.open(.{
        .base = true,
        .package = true,
        .string = true,
        .utf8 = true,
        .table = true,
        .math = true,
    });
    _ = try l.getGlobal("package");
    const require_path = try std.fs.path.joinZ(self.allocator, &.{ self.data_dir_path, "?.lua" });
    defer self.allocator.free(require_path);

    _ = l.pushBytes(require_path);
    l.setField(-2, "path");
    l.pop(2);
}

pub fn createSession(self: *Engine) !*Session {
    const session = try Session.create(self.allocator, self.assets);
    return session;
}

pub const Arguments = struct {
    data_dir_path: ?[]const u8 = null,

    pub fn initFromCommandLineArgs(allocator: Allocator) !Arguments {
        var self = Arguments{};
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();
        _ = args.next();

        const opt_dataroot = "-datapath=";

        while (args.next()) |arg| {
            if (std.mem.startsWith(u8, arg, opt_dataroot)) {
                if (arg.len == opt_dataroot.len) {
                    std.log.err("option {s} requires argument", .{opt_dataroot});
                    return error.MissingParameter;
                }
                self.data_dir_path = try allocator.dupe(u8, arg[opt_dataroot.len..]);
            }
        }
        return self;
    }

    pub fn deinit(self: Arguments, allocator: Allocator) void {
        if (self.data_dir_path) |path| {
            allocator.free(path);
        }
    }
};
