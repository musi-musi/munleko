const std = @import("std");
const ziglua = @import("ziglua");
const mun = @import("mun");
const nm = @import("nm");

pub const Session = @import("engine/Session.zig");
pub const Assets = @import("engine/Assets.zig");
pub const World = @import("engine/World.zig");
pub const Player = @import("engine/Player.zig");
pub const leko = @import("engine/leko.zig");

const Allocator = std.mem.Allocator;

const Lua = ziglua.Lua;

allocator: Allocator,
arguments: Arguments,
data_root_path: []const u8,

lua: Lua,
assets: *Assets,

const Engine = @This();

pub fn create(allocator: Allocator, arguments: Arguments) !*Engine {
    const self = try allocator.create(Engine);
    errdefer allocator.destroy(self);
    self.* = Engine{
        .allocator = allocator,
        .arguments = arguments,
        .data_root_path = undefined,
        .lua = try Lua.init(allocator),
        .assets = try Assets.create(allocator),
    };
    errdefer self.lua.deinit();
    if (arguments.data_root_path) |data_root_path| {
        const cwd = std.fs.cwd();
        self.data_root_path = try cwd.realpathAlloc(allocator, data_root_path);
    } else {
        const exe_dir_path = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(exe_dir_path);
        self.data_root_path = try std.fs.path.resolve(allocator, &.{ exe_dir_path, "data" });
    }
    errdefer allocator.free(self.data_root_path);
    try self.initLua();
    return self;
}

pub fn destroy(self: *Engine) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    allocator.free(self.data_root_path);
    self.lua.deinit();
    self.assets.destroy();
}

pub fn load(self: *Engine) !void {
    const l = &self.lua;
    const lua_main_path = try std.fs.path.joinZ(self.allocator, &.{ self.data_root_path, "main.lua" });
    defer self.allocator.free(lua_main_path);
    try l.doFile(lua_main_path);
    try self.assets.load(l, self.data_root_path);
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
    const require_path = try std.fs.path.joinZ(self.allocator, &.{ self.data_root_path, "?.lua" });
    defer self.allocator.free(require_path);

    _ = l.pushString(require_path);
    l.setField(-2, "path");
    l.pop(2);
}

pub fn createSession(self: *Engine) !*Session {
    return Session.create(self.allocator);
}

pub const Arguments = struct {
    data_root_path: ?[]const u8 = null,

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
                self.data_root_path = try allocator.dupe(u8, arg[opt_dataroot.len..]);
            }
        }
        return self;
    }

    pub fn deinit(self: Arguments, allocator: Allocator) void {
        if (self.data_root_path) |path| {
            allocator.free(path);
        }
    }
};
