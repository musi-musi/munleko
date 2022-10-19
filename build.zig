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
    // client.addSystemIncludeDir("");
    
    if (target.getOsTag() == .windows) {
        client.step.dependOn(
            &b.addInstallBinFile(.{.path = "pkg/window/c/glfw3.dll"}, "glfw3.dll").step,
        );
    }

    client.addIncludeDir("pkg/lua/c");


    const run_cmd = client.run();

    sequence(&[_]*Step{
        &b.addInstallArtifact(client).step,
        &run_cmd.step,
        b.step("run", "Run the app"),
    });

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // exe.addLibPath("munleko/c");
    // exe.linkSystemLibrary("glfw3");
    
    // const c_flags = .{ "-std=c99", "-I./munleko/c/"};

    // exe.addIncludeDir("munleko/c/");
    // exe.addIncludeDir("munleko/c/glad/include");
    // exe.addCSourceFile("munleko/c/glad/src/glad.c", &c_flags);
    // exe.addCSourceFile("munleko/c/stb_image.c", &c_flags);


    // const flags: []const []const u8 = &.{
    //     "-std=c++11",
    //     "-I./munleko/c",
    //     "-I./munleko/c/glad/include",
    //     "-I./munleko/c/cimgui",
    //     "-I./munleko/c/cimgui/imgui",
    //     "-I./munleko/c/imgui_impl",
    // };


    // exe.addCSourceFile("munleko/c/imgui_impl.cpp", flags);

    // exe.addIncludeDir("munleko/c/cimgui");
    // exe.addIncludeDir("munleko/c/cimgui/imgui");
    // exe.addCSourceFile("munleko/c/cimgui/cimgui.cpp", flags);
    // exe.addCSourceFile("munleko/c/cimgui/imgui/imgui.cpp", flags);
    // exe.addCSourceFile("munleko/c/cimgui/imgui/imgui_draw.cpp", flags);
    // exe.addCSourceFile("munleko/c/cimgui/imgui/imgui_demo.cpp", flags);
    // exe.addCSourceFile("munleko/c/cimgui/imgui/imgui_tables.cpp", flags);
    // exe.addCSourceFile("munleko/c/cimgui/imgui/imgui_widgets.cpp", flags);

    // exe.addIncludeDir("munleko/c/imgui_impl");
    // exe.addCSourceFile("munleko/c/imgui_impl/imgui_impl_glfw.cpp", flags);
    // exe.addCSourceFile("munleko/c/imgui_impl/imgui_impl_opengl3.cpp", flags);

    // exe.linkLibCpp();
    // exe.linkLibC();
    // exe.install();

    // const run_cmd = exe.run();
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);

    // const exe_tests = b.addTest("srmunleko/c/main.zig");
    // exe_tests.setBuildMode(mode);

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&exe_tests.step);
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


    // b.installBinFile("munleko/c/glfw3.dll", "glfw3.dll");


    const exe = b.addExecutable("munleko", "src/" ++ frontend_id ++ ".zig");


    inline for (std.meta.declarations(pkgs)) |decl| {
        const pkg = @field(pkgs, decl.name);
        if (@TypeOf(pkg) == Pkg) {
            exe.addPackage(pkg);
        }
    }


    // const build_src =
    // \\pub const FrontendId = enum {
    // \\    client,
    // \\    server,
    // \\};
    // \\
    // \\
    // ;

    // const build_step = b.addWriteFile("build.zig", build_src ++ "pub const frontend: FrontendId = ." ++ frontend_id ++ ";\n");
    // exe.step.dependOn(&build_step.step);
    // const build_pkg = Pkg {
    //     .name = "build",
    //     .path = build_step.getFileSource("build.zig").?,
    // };
    // exe.addPackage(build_pkg);


    return exe;
}