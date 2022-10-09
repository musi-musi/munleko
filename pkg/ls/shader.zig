const std = @import("std");
const gl = @import("gl");
const ls = @import("../ls.zig");

const GlslPrimitive = gl.GlslPrimitive;

pub const VertexIn = struct {
    location: u32,
    name: []const u8,
    attr_type: GlslPrimitive,
};

pub const FragmentOut = struct {
    location: u32,
    name: []const u8,
    attr_type: GlslPrimitive,
};

pub const Uniform = struct {
    name: []const u8,
    uniform_type: GlslPrimitive,
    array_len: ?usize = null,
};


pub fn vertIn(location: u32, name: []const u8, attr_type: GlslPrimitive) VertexIn {
    return .{
        .location = location,
        .name = name,
        .attr_type = attr_type,
    };
}

pub fn fragOut(location: u32, name: []const u8, attr_type: GlslPrimitive) FragmentOut {
    return .{
        .location = location,
        .name = name,
        .attr_type = attr_type,
    };
}

pub fn uniform(name: []const u8, uniform_type: GlslPrimitive) Uniform {
    return .{
        .name = name,
        .uniform_type = uniform_type,
    };
}

pub fn uniformArray(name: []const u8, uniform_type: GlslPrimitive, array_len: usize) Uniform {
    return .{
        .name = name,
        .uniform_type = uniform_type,
        .array_len = array_len,
    };
}

pub const ShaderConfig = struct {
    vert_inputs: []const VertexIn = &.{},
    frag_outputs: []const FragmentOut = &.{ fragOut(0, "color", .vec4)},
    uniforms: []const Uniform = &.{},

    fn header(comptime cfg: ShaderConfig, comptime stage: gl.StageType) []const u8 {
        const Fmt = struct {
            pub fn format(_: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
                try w.writeAll("#line 1 413\n");
                const cfg = self.config;
                for (cfg.uniforms) |u| {
                    try w.print("uniform {s} u_{s}", .{@tagName(u.uniform_type), u.name});
                    if (u.array_len) |len| {
                        try w.print("[{d}]", .{len});
                    }
                    try w.writeAll(";\n");
                }
                if (stage == .vertex) {
                    for (cfg.vert_inputs) |vi| {
                        try w.print("layout (location = {d}) in {s} v_{s};\n", .{vi.location, @tagName(vi.attr_type), vi.name});
                    }
                    try w.writeAll("#define v2f out\n");
                    try w.writeAll("#define vertex main\n");
                }
                if (stage == .fragment) {
                    for (cfg.frag_outputs) |fo| {
                        try w.print("layout (location = {d}) out {s} f_{s};\n", .{fo.location, @tagName(fo.attr_type), fo.name});
                    }
                    try w.writeAll("#define v2f in\n");
                    try w.writeAll("#define fragment main\n");
                }
            }
        };
        return std.fmt.comptimePrint("{}", .{Fmt{}});
    }

    fn UniformTag(comptime self: ShaderConfig) type {
        if (self.uniforms.len == 0) {
            return void;
        }
        var uniform_tag_fields: [self.uniforms.len]TypeInfo.EnumField = undefined;
        for (cfg.uniforms) |uniform, i| {
            uniform_tag_fields[i] = .{
                .name = uniform.name,
                .value = i,
            };
        }
        return @Type(.{
            .Enum = .{
                .layout = .Auto,
                .tag_type = usize,
                .fields = &uniform_tag_fields,
                .decls = &.{},
                .is_exhaustive = true,
            },
        });
    }

    fn UniformLocations(comptime self: ShaderConfig) type {
        return [self.uniforms.len]gl.UniformLocation;
    }

};


const TypeInfo = std.builtin.TypeInfo;
pub fn Shader(comptime cfg: ShaderConfig) type {


    return struct {

        program: gl.Program,
        uniform_locations: cfg.UniformLocations(),

        pub const UniformTag = cfg.UniformTag();

        pub fn UniformValue(comptime tag: UniformTag) type {
            const u = cfg.uniforms[@enumToInt(tag)];
            const U = u.uniform_type.Type();
            if (u.array_len == null) {
                return U;
            }
            else {
                return []const U;
            }
        }

        const Self = @This();

        pub fn init(source: []const u8) !Self {

        }

        pub fn setUniform(self: Self, comptime tag: UniformTag, value: UniformValue(tag)) void {
            const u = cfg.uniforms[@enumToInt(tag)];
            if (u.array_len == null) {
                self.program.setUniform(self.uniform_locations[@enumToInt(tag)], u.uniform_type, value);
            }
            else {
                self.program.setUniformArray(self.uniform_locations[@enumToInt(tag)], u.uniform_type, value);
            }
        }

    };
}