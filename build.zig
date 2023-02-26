const std = @import("std");
const ziglua = @import("lib/ziglua/build.zig");

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

    client.addPackage(pkgs.pkg("window", &.{pkgs.util}));

    client.addIncludePath("lib/window/c");
    client.addLibraryPath("lib/window/c/");
    client.linkSystemLibrary("glfw3");

    const gl = pkgs.pkg("gl", null);
    client.addPackage(gl);
    const ls = pkgs.pkg("ls", &.{gl});
    client.addPackage(ls);

    client.addIncludePath("lib/gl/c");
    client.addCSourceFile("lib/gl/c/glad.c", &.{"-std=c99"});

    client.addIncludePath("src/munleko/engine/c");
    client.addCSourceFile("src/munleko/engine/c/stb_image.c", &.{"-std=c99"});
    if (target.getOsTag() == .windows) {
        client.step.dependOn(
            &b.addInstallBinFile(.{ .path = "lib/window/c/glfw3.dll" }, "glfw3.dll").step,
        );
    }

    const install_client = &b.addInstallArtifact(client).step;
    const run_cmd = client.run();
    run_cmd.addArg("-datapath=./data");

    sequence(&[_]*Step{
        install_client,
        b.default_step,
    });

    sequence(&[_]*Step{
        install_client,
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

    fn pkg(comptime name: []const u8, deps: ?[]const Pkg) Pkg {
        return Pkg{
            .name = name,
            .source = .{ .path = "lib/" ++ name ++ "/lib.zig" },
            .dependencies = deps,
        };
    }
};

fn buildBase(b: *std.build.Builder, comptime frontend_id: []const u8) *std.build.LibExeObjStep {
    const exe = b.addExecutable("munleko", "src/" ++ frontend_id ++ "_main.zig");
    const lua = ziglua.linkAndPackage(b, exe, .{});
    exe.addPackage(lua);
    const mun = Pkg{
        .name = "mun",
        .source = .{ .path = "lib/mun/lib.zig" },
        .dependencies = &.{lua},
    };
    exe.addPackage(mun);

    inline for (comptime std.meta.declarations(pkgs)) |decl| {
        const pkg = @field(pkgs, decl.name);
        if (@TypeOf(pkg) == Pkg) {
            exe.addPackage(pkg);
        }
    }

    return exe;
}
