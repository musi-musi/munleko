const std = @import("std");
const zgui = @import("lib/zig-gamedev/libs/zgui/build.zig");

const Build = std.Build;
const Step = Build.Step;
const Module = Build.Module;
const ModuleDependency = Build.ModuleDependency;
// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "munleko",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/client_main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    addModules(b, exe, .{
        .target = target,
        .optimize = optimize,
    });

    const zgui_pkg = zgui.package(b, target, optimize, .{ .options = .{ .backend = .no_backend } });
    zgui_pkg.link(exe);

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    run_cmd.addArg("-datapath=data");
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

pub fn sequence(steps: []const *Step) void {
    var i: usize = 1;
    while (i < steps.len) : (i += 1) {
        steps[i].dependOn(steps[i - 1]);
    }
}

fn createLibModule(b: *Build, comptime name: []const u8, deps: []const ModuleDependency) *Module {
    return b.createModule(.{
        .source_file = .{ .path = "lib/" ++ name ++ "/lib.zig" },
        .dependencies = deps,
    });
}

fn addModules(b: *Build, exe: *Build.CompileStep, args: anytype) void {
    const ziglua = b.dependency("ziglua", args);
    exe.addModule("ziglua", ziglua.module("ziglua"));
    exe.linkLibrary(ziglua.artifact("lua"));

    exe.linkLibC();
    const oko = createLibModule(b, "oko", &.{});
    exe.addModule("oko", oko);
    const util = createLibModule(b, "util", &.{
        .{ .name = "oko", .module = oko },
    });
    exe.addModule("util", util);
    const window = createLibModule(b, "window", &.{
        .{ .name = "util", .module = util },
    });
    exe.addModule("window", window);
    const mun = createLibModule(b, "mun", &.{
        .{ .name = "ziglua", .module = ziglua.module("ziglua") },
    });
    exe.addModule("mun", mun);

    exe.addIncludePath(.{ .path = "lib/window/c" });
    exe.addLibraryPath(.{ .path = "lib/window/c/" });
    exe.linkSystemLibrary("glfw3");
    if (exe.target.getOsTag() == .windows) {
        exe.step.dependOn(
            &b.addInstallBinFile(.{ .path = "lib/window/c/glfw3.dll" }, "glfw3.dll").step,
        );
    }

    const nm = createLibModule(b, "nm", &.{});
    exe.addModule("nm", nm);
    const gl = createLibModule(b, "gl", &.{});
    exe.addModule("gl", gl);
    exe.addIncludePath(.{ .path = "lib/gl/c" });
    exe.addCSourceFile(.{ .file = .{ .path = "lib/gl/c/glad.c" }, .flags = &.{"-std=c99"} });

    const ls = createLibModule(b, "ls", &.{
        .{ .name = "gl", .module = gl },
    });
    exe.addModule("ls", ls);

    exe.addIncludePath(.{ .path = "src/munleko/engine/c" });
    exe.addCSourceFile(.{ .file = .{ .path = "src/munleko/engine/c/stb_image.c" }, .flags = &.{"-std=c99"} });
    exe.addIncludePath(.{ .path = "src/munleko/client/gui/c" });
    exe.addIncludePath(.{ .path = "lib/zig-gamedev/libs/zgui/libs/imgui" });
    exe.addCSourceFile(.{ .file = .{ .path = "src/munleko/client/gui/c/imgui_impl_opengl3.cpp" }, .flags = &.{"-fno-sanitize=undefined"} });
    exe.addCSourceFile(.{ .file = .{ .path = "src/munleko/client/gui/c/imgui_impl_glfw.cpp" }, .flags = &.{"-fno-sanitize=undefined"} });
    exe.addCSourceFile(.{ .file = .{ .path = "src/munleko/client/gui/c/imgui_backend.cpp" }, .flags = &.{"-fno-sanitize=undefined"} });
}
