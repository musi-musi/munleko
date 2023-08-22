const std = @import("std");

const Allocator = std.mem.Allocator;

const Dir = std.fs.Dir;

const DataDir = @This();

allocator: Allocator,
path: []const u8,
dir: Dir,

pub fn open(allocator: Allocator, path_opt: ?[]const u8) !DataDir {
    const path = try getPathOrDefault(allocator, path_opt);
    errdefer allocator.free(path);
    var dir = try std.fs.openDirAbsolute(path, .{});
    errdefer dir.close();

    dir.makeDir("saves") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    return DataDir{
        .allocator = allocator,
        .path = path,
        .dir = dir,
    };
}

pub fn close(self: *DataDir) void {
    const allocator = self.allocator;
    allocator.free(self.path);
    self.dir.close();
}

fn getPathOrDefault(allocator: Allocator, path_opt: ?[]const u8) ![]const u8 {
    if (path_opt) |data_dir_path| {
        const cwd = std.fs.cwd();
        return cwd.realpathAlloc(allocator, data_dir_path);
    } else {
        const exe_dir_path = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(exe_dir_path);
        return std.fs.path.resolve(allocator, &.{ exe_dir_path, "data" });
    }
}
