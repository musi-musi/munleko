const std = @import("std");
const ziglua = @import("ziglua");
const nm = @import("nm");

pub const Session = @import("engine/Session.zig");
pub const Assets = @import("engine/Assets.zig");
pub const World = @import("engine/World.zig");
pub const Player = @import("engine/Player.zig");
pub const leko = @import("engine/leko.zig");
pub const Save = @import("engine/Save.zig");
pub const DataDir = @import("engine/DataDir.zig");
pub const Mun = @import("engine/Mun.zig");

const Allocator = std.mem.Allocator;

const Lua = ziglua.Lua;

const Dir = std.fs.Dir;

allocator: Allocator,
arguments: Arguments,
data_dir: DataDir,
saves_root_path: []const u8,

mun: *Mun,
assets: *Assets,

const Engine = @This();

pub fn create(allocator: Allocator, arguments: Arguments) !*Engine {
    const self = try allocator.create(Engine);
    errdefer allocator.destroy(self);
    self.allocator = allocator;
    self.arguments = arguments;

    self.assets = try Assets.create(allocator);
    errdefer self.assets.destroy();

    self.data_dir = try DataDir.open(allocator, arguments.data_dir_path);
    errdefer self.data_dir.close();

    self.mun = try Mun.create(allocator, self.data_dir.path);
    errdefer self.mun.destroy();

    const saves_root_path = try std.fs.path.resolve(allocator, &.{ self.data_dir.path, "saves" });
    errdefer allocator.free(saves_root_path);

    if (std.fs.makeDirAbsolute(saves_root_path)) {} else |err| {
        if (err != std.posix.MakeDirError.PathAlreadyExists) {
            return err;
        }
    }
    self.saves_root_path = saves_root_path;

    return self;
}

pub fn destroy(self: *Engine) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.data_dir.close();
    allocator.free(self.saves_root_path);
    self.mun.destroy();
    self.assets.destroy();
}

pub fn load(self: *Engine) !void {
    try self.mun.requireModule("main");
    try self.assets.load(self.mun.lua, self.data_dir.dir);
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
