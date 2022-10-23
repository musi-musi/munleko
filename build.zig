const std = @import("std");

const Pkg = std.build.Pkg;
const FileSource = std.build.FileSource;

const Allocator = std.mem.Allocator;
const Step = std.build.Step;
const Builder = std.build.Builder;

pub fn sequence(steps: []const *Step) void {
    var i: usize = 1;
    while (i < steps.len) : (i += 1) {
        steps[i].dependOn(steps[i - 1]);
    }
    
}

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const client = buildBase(b, "client");
    client.linkLibC();
    client.setBuildMode(mode);
    client.setTarget(target);

    client.addPackage(pkgs.pkg("window", &.{ pkgs.util }));

    client.addIncludeDir("pkg/window/c");
    client.addLibPath("pkg/window/c/");
    client.linkSystemLibrary("glfw3");

    const gl = pkgs.pkg("gl", null);
    client.addPackage(gl);

    const ls = pkgs.pkg("ls", &.{ gl });
    client.addPackage(ls);

    client.addIncludeDir("pkg/gl/c");
    client.addCSourceFile("pkg/gl/c/glad.c", &.{"-std=c99"});
    
    if (target.getOsTag() == .windows) {
        client.step.dependOn(
            &b.addInstallBinFile(.{.path = "pkg/window/c/glfw3.dll"}, "glfw3.dll").step,
        );
    }

    client.addIncludeDir("lua/src");

    const lua = try createLuaStep(b);

    client.linkLibrary(lua);

    const run_cmd = client.run();

    sequence(&[_]*Step{
        &b.addInstallArtifact(client).step,
        &run_cmd.step,
        b.step("run", "Run the app"),
    });

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

const fs = std.fs;




const pkgs = struct {

    const nm = pkg("nm", null);
    const util = pkg("util", null);
    const lua = pkg("lua", null);

    fn pkg(comptime name: []const u8, deps: ?[]const Pkg) Pkg {
        return Pkg {
            .name = name,
            .path = .{ .path = "pkg/" ++ name ++ ".zig" },
            .dependencies = deps,
        };
    }
};


fn buildBase(b: *std.build.Builder, comptime frontend_id: []const u8) *std.build.LibExeObjStep {


    const exe = b.addExecutable("munleko", "src/" ++ frontend_id ++ ".zig");


    inline for (std.meta.declarations(pkgs)) |decl| {
        const pkg = @field(pkgs, decl.name);
        if (@TypeOf(pkg) == Pkg) {
            exe.addPackage(pkg);
        }
    }


    return exe;
}

fn createLuaStep(b: *Builder) !*std.build.LibExeObjStep {
    const lua = b.addStaticLibrary("lua", null);
    var dir = try std.fs.cwd().openDir("lua/src", .{.iterate = true});
    defer dir.close();

    lua.linkLibC();
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".c")) {
            const path = try std.fmt.allocPrint(b.allocator, "lua/src/{s}", .{entry.name});
            // std.log.info("{s}", .{path});
            lua.addCSourceFile(path, &.{"-std=c99"});
        }
    }

    lua.addIncludeDir("lua/src");

    return lua;
}