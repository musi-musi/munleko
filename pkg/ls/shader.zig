const std = @import("std");
const gl = @import("gl");
const ls = @import("../ls.zig");

const GlslPrimitive = gl.GlslPrimitive;

pub const VertInDef = struct {
    location: u32,
    name: []const u8,
    attr_type: GlslPrimitive,
};

pub const FragOutDef = struct {
    location: u32,
    name: []const u8,
    attr_type: GlslPrimitive,
};

pub const UniformDef = struct {
    name: []const u8,
    uniform_type: GlslPrimitive,
    array_len: ?usize = null,
};


pub fn defVertIn(location: u32, name: []const u8, attr_type: GlslPrimitive) VertInDef {
    return .{
        .location = location,
        .name = name,
        .attr_type = attr_type,
    };
}

pub fn defFragOut(location: u32, name: []const u8, attr_type: GlslPrimitive) FragOutDef {
    return .{
        .location = location,
        .name = name,
        .attr_type = attr_type,
    };
}

pub fn defUniform(name: []const u8, uniform_type: GlslPrimitive) UniformDef {
    return .{
        .name = name,
        .uniform_type = uniform_type,
    };
}

pub fn defUniformArray(name: []const u8, uniform_type: GlslPrimitive, array_len: usize) UniformDef {
    return .{
        .name = name,
        .uniform_type = uniform_type,
        .array_len = array_len,
    };
}

pub const ShaderDefs = struct {
    vert_inputs: []const VertInDef = &.{},
    frag_outputs: []const FragOutDef = &.{ defFragOut(0, "color", .vec4)},
    uniforms: []const UniformDef = &.{},

    fn UniformTag(comptime self: ShaderDefs) type {
        if (self.uniforms.len == 0) {
            return void;
        }
        var uniform_tag_fields: [self.uniforms.len]TypeInfo.EnumField = undefined;
        for (self.uniforms) |uniform, i| {
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

    fn UniformLocations(comptime self: ShaderDefs) type {
        return [self.uniforms.len]gl.UniformLocation;
    }

    pub fn append(comptime self: ShaderDefs, comptime other: ShaderDefs) ShaderDefs {
        return .{
            .vert_inputs = self.vert_inputs ++ other.vert_inputs,
            .frag_outputs = self.frag_outputs ++ other.frag_outputs,
            .uniforms = self.uniforms ++ other.uniforms,
        };
    }

};


fn removeDupes(comptime T: type, comptime in: []const T) []const T {
    @setEvalBranchQuota(10000);
    var out: []const T = &.{};
    for (in) |a| {
        for (out) |b| {
            if (std.mem.eql(u8, a.name, b.name)) {
                break;
            }
        }
        else {
            out = out ++ &[1]T{ a };
        }
    }
    return out;
}

pub const ShaderSourceConfig = struct {
    version: ShaderSourceVersion = .{},
};

pub const ShaderSourceVersion = struct {

    number: u32 = 330,
    profile: Profile = .core,

    pub const Profile = enum {
        core,
        compatibility,
    };
};

const TypeInfo = std.builtin.TypeInfo;
pub fn Shader(comptime shader_defs: ShaderDefs) type {

    return struct {

        program: gl.Program,
        uniform_locations: defs.UniformLocations(),

        pub const defs = ShaderDefs {
            .vert_inputs = removeDupes(VertInDef, shader_defs.vert_inputs),
            .frag_outputs = removeDupes(FragOutDef, shader_defs.frag_outputs),
            .uniforms = removeDupes(UniformDef, shader_defs.uniforms),
        };
        // pub const defs = shader_defs;

        pub const UniformTag = defs.UniformTag();

        pub fn UniformValue(comptime tag: UniformTag) type {
            const u = defs.uniforms[@enumToInt(tag)];
            const U = u.uniform_type.Type();
            if (u.array_len == null) {
                return U;
            }
            else {
                return []const U;
            }
        }

        const Self = @This();

        pub fn create(comptime src_cfg: ShaderSourceConfig, source: []const u8) !Self {
            const allocator = std.heap.page_allocator;

            const vert_source = try genSource(.vertex, src_cfg, allocator, source);
            defer allocator.free(vert_source);
            const frag_source = try genSource(.fragment, src_cfg, allocator, source);
            defer allocator.free(frag_source);

            var program = gl.Program.create();
            errdefer program.destroy();

            var vert_stage = gl.VertexStage.create();
            defer vert_stage.destroy();
            vert_stage.source(vert_source);
            try vert_stage.compile();

            var frag_stage = gl.FragmentStage.create();
            defer frag_stage.destroy();
            frag_stage.source(frag_source);
            try frag_stage.compile();

            program.attach(vert_stage);
            program.attach(frag_stage);
            try program.link();

            var locations: defs.UniformLocations() = undefined;
            inline for (defs.uniforms) |uniform, i| {
                locations[i] = program.getUniformLocation(uniform ++ "");
            }

            return Self {
                .program = program,
                .uniform_locations = locations,
            };
        }

        pub fn destroy(self: Self) void {
            self.program.destroy();
        }

        fn genSource(comptime stage: gl.StageType, comptime src_cfg: ShaderSourceConfig, allocator: std.mem.Allocator, body: []const u8) ![]const u8 {
            const version = src_cfg.version;
            var source = std.ArrayListUnmanaged(u8){};
            errdefer source.deinit(allocator);
            const w = source.writer(allocator);
            try w.print("#version {d} {s}\n", .{version.number, @tagName(version.profile)});
            for (defs.uniforms) |u| {
                try w.print("uniform {s} u_{s}", .{@tagName(u.uniform_type), u.name});
                if (u.array_len) |len| {
                    try w.print("[{d}]", .{len});
                }
                try w.writeAll(";\n");
            }
            if (stage == .vertex) {
                for (defs.vert_inputs) |vi| {
                    try w.print("layout (location = {d}) in {s} v_{s};\n", .{vi.location, @tagName(vi.attr_type), vi.name});
                }
                try w.writeAll("#define vf out\n");
                try w.writeAll("#define STAGE_VERTEX\n");
            }
            if (stage == .fragment) {
                for (defs.frag_outputs) |fo| {
                    try w.print("layout (location = {d}) out {s} f_{s};\n", .{fo.location, @tagName(fo.attr_type), fo.name});
                }
                try w.writeAll("#define vf in\n");
                try w.writeAll("#define STAGE_FRAGMENT\n");
            }
            try w.writeAll("#line 1 0\n");
            try w.writeAll(body);
            return source.toOwnedSlice(allocator);
        }

        pub fn setUniform(self: Self, comptime tag: UniformTag, value: UniformValue(tag)) void {
            const u = defs.uniforms[@enumToInt(tag)];
            if (u.array_len == null) {
                self.program.setUniform(self.uniform_locations[@enumToInt(tag)], u.uniform_type, value);
            }
            else {
                self.program.setUniformArray(self.uniform_locations[@enumToInt(tag)], u.uniform_type, value);
            }
        }

        pub fn use(self: Self) void {
            self.program.use();
        }

    };
}