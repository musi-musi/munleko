const std = @import("std");
const gl = @import("gl");

pub const MeshConfig = struct {
    buffers: []const MeshBufferDef,
    index_type: gl.IndexType = .uint,
    primitive_type: gl.PrimitiveType = .triangles,

    pub fn vertexInDefs(comptime self: MeshConfig) []const VertInDef {
        var vert_inputs: []const VertInDef = &.{};
        var location = 0;
        for (self.buffers) |buffer| {
            const T = buffer.data_type;
            for (std.meta.fields(T)) |field| {
                vert_inputs = vert_inputs ++ &[_]VertInDef{defVertIn(location, field.name, gl.GlslPrimitive.fromType(field.type))};
                location += 1;
            }
        }
        return vert_inputs;
    }
};

pub const MeshBufferDef = struct {
    data_type: type,
    divisor: u32 = 0,
};

pub fn defMeshBuffer(comptime data_type: type, comptime divisor: u32) MeshBufferDef {
    return .{
        .data_type = data_type,
        .divisor = divisor,
    };
}

pub fn defVertexBuffer(comptime data_type: type) MeshBufferDef {
    return defMeshBuffer(data_type, 0);
}

pub fn defInstanceBuffer(comptime data_type: type) MeshBufferDef {
    return defMeshBuffer(data_type, 1);
}

pub fn Mesh(comptime mesh_cfg: MeshConfig) type {
    return struct {
        array: gl.Array,

        pub const cfg = mesh_cfg;
        pub const vertex_in_defs = cfg.vertexInDefs();

        const Self = @This();

        pub fn create() Self {
            const array = gl.Array.create();
            comptime var a: u32 = 0;
            inline for (cfg.buffers, 0..) |buffer, b| {
                const T = buffer.data_type;
                inline for (std.meta.fields(T)) |field| {
                    array.setAttributeFormat(
                        @as(u32, @intCast(b)),
                        a,
                        comptime gl.AttrType.fromType(field.type),
                        @offsetOf(buffer.data_type, field.name),
                    );
                    a += 1;
                }
                if (buffer.divisor != 0) {
                    array.setBindingDivisor(@as(u32, @intCast(b)), buffer.divisor);
                }
            }
            return Self{
                .array = array,
            };
        }

        pub fn destroy(self: Self) void {
            self.array.destroy();
        }

        pub fn Buffer(comptime binding: u32) type {
            return gl.Buffer(cfg.buffers[binding].data_type);
        }

        pub fn setBuffer(self: Self, comptime binding: u32, buffer: Buffer(binding)) void {
            self.array.setVertexBuffer(binding, buffer, 0);
        }

        pub const IndexBuffer = gl.Buffer(cfg.index_type.Type());

        pub fn setIndexBuffer(self: Self, buffer: IndexBuffer) void {
            self.array.setIndexBuffer(buffer);
        }

        pub fn bind(self: Self) void {
            self.array.bind();
        }

        pub fn drawAssumeBound(self: Self, index_count: usize) void {
            _ = self;
            gl.drawElements(cfg.primitive_type, index_count, cfg.index_type);
        }

        pub fn drawInstancedAssumeBound(self: Self, index_count: usize, instance_count: usize) void {
            _ = self;
            gl.drawElementsInstanced(cfg.primitive_type, index_count, cfg.index_type, instance_count);
        }
    };
}

const GlslPrimitive = gl.GlslPrimitive;

pub const VertInDef = struct {
    location: u32,
    name: [:0]const u8,
    attr_type: GlslPrimitive,
};

pub const FragOutDef = struct {
    location: u32,
    name: [:0]const u8,
    attr_type: GlslPrimitive,
};

pub const UniformDef = struct {
    name: [:0]const u8,
    uniform_type: GlslPrimitive,
    array_len: ?usize = null,
};

pub const SamplerDef = struct {
    name: [:0]const u8,
    sampler_type: SamplerType,
};

pub const SamplerType = enum {
    sampler_2d,
    sampler_2d_array,

    fn glslKeyword(self: SamplerType) []const u8 {
        return switch (self) {
            .sampler_2d => "sampler2D",
            .sampler_2d_array => "sampler2DArray",
        };
    }
};

pub fn defVertIn(location: u32, name: [:0]const u8, attr_type: GlslPrimitive) VertInDef {
    return .{
        .location = location,
        .name = name,
        .attr_type = attr_type,
    };
}

pub fn defFragOut(location: u32, name: [:0]const u8, attr_type: GlslPrimitive) FragOutDef {
    return .{
        .location = location,
        .name = name,
        .attr_type = attr_type,
    };
}

pub fn defUniform(name: [:0]const u8, uniform_type: GlslPrimitive) UniformDef {
    return .{
        .name = name,
        .uniform_type = uniform_type,
    };
}

pub fn defUniformArray(name: [:0]const u8, uniform_type: GlslPrimitive, array_len: usize) UniformDef {
    return .{
        .name = name,
        .uniform_type = uniform_type,
        .array_len = array_len,
    };
}

pub fn defSampler(name: [:0]const u8, sampler_type: SamplerType) SamplerDef {
    return .{
        .name = name,
        .sampler_type = sampler_type,
    };
}

pub const ShaderDefs = struct {
    vert_inputs: []const VertInDef = &.{},
    frag_outputs: []const FragOutDef = &.{defFragOut(0, "color", .vec4)},
    uniforms: []const UniformDef = &.{},
    samplers: []const SamplerDef = &.{},
    source_modules: []const []const u8 = &.{},

    fn UniformTag(comptime self: ShaderDefs) type {
        if (self.uniforms.len == 0) {
            return void;
        }
        var uniform_tag_fields: [self.uniforms.len]Type.EnumField = undefined;
        for (self.uniforms, 0..) |uniform, i| {
            uniform_tag_fields[i] = .{
                .name = uniform.name,
                .value = i,
            };
        }
        return @Type(.{
            .Enum = .{
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

    fn SamplerTag(comptime self: ShaderDefs) type {
        if (self.samplers.len == 0) {
            return void;
        }
        var sampler_tag_fields: [self.samplers.len]Type.EnumField = undefined;
        for (self.samplers, 0..) |sampler, i| {
            sampler_tag_fields[i] = .{
                .name = sampler.name,
                .value = i,
            };
        }
        return @Type(.{
            .Enum = .{
                .tag_type = usize,
                .fields = &sampler_tag_fields,
                .decls = &.{},
                .is_exhaustive = true,
            },
        });
    }

    fn SamplerLocations(comptime self: ShaderDefs) type {
        return [self.samplers.len]gl.UniformLocation;
    }

    pub fn append(comptime self: ShaderDefs, comptime other: ShaderDefs) ShaderDefs {
        return .{
            .vert_inputs = self.vert_inputs ++ other.vert_inputs,
            .frag_outputs = self.frag_outputs ++ other.frag_outputs,
            .uniforms = self.uniforms ++ other.uniforms,
            .samplers = self.samplers ++ other.samplers,
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
        } else {
            out = out ++ &[1]T{a};
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

const Type = std.builtin.Type;
pub fn Shader(comptime shader_defs: ShaderDefs) type {
    return struct {
        program: gl.Program,
        uniform_locations: defs.UniformLocations(),
        sampler_locations: defs.SamplerLocations(),

        pub const defs = ShaderDefs{
            .vert_inputs = removeDupes(VertInDef, shader_defs.vert_inputs),
            .frag_outputs = removeDupes(FragOutDef, shader_defs.frag_outputs),
            .uniforms = removeDupes(UniformDef, shader_defs.uniforms),
            .samplers = removeDupes(SamplerDef, shader_defs.samplers),
        };
        // pub const defs = shader_defs;

        pub const UniformTag = defs.UniformTag();
        pub const SamplerTag = defs.SamplerTag();

        pub fn UniformValue(comptime tag: UniformTag) type {
            const u = defs.uniforms[@intFromEnum(tag)];
            const U = u.uniform_type.Type();
            if (u.array_len == null) {
                return U;
            } else {
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

            var uniform_locations: defs.UniformLocations() = undefined;
            inline for (defs.uniforms, 0..) |uniform, i| {
                uniform_locations[i] = program.getUniformLocation("u_" ++ uniform.name ++ "");
            }

            var sampler_locations: defs.SamplerLocations() = undefined;
            inline for (defs.samplers, 0..) |sampler, i| {
                sampler_locations[i] = program.getUniformLocation("s_" ++ sampler.name ++ "");
            }

            return Self{
                .program = program,
                .uniform_locations = uniform_locations,
                .sampler_locations = sampler_locations,
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
            try w.print("#version {d} {s}\n", .{ version.number, @tagName(version.profile) });
            for (defs.uniforms) |u| {
                try w.print("uniform {s} u_{s}", .{ @tagName(u.uniform_type), u.name });
                if (u.array_len) |len| {
                    try w.print("[{d}]", .{len});
                }
                try w.writeAll(";\n");
            }
            for (defs.samplers) |s| {
                try w.print("uniform {s} s_{s};\n", .{ s.sampler_type.glslKeyword(), s.name });
            }
            if (stage == .vertex) {
                for (defs.vert_inputs) |vi| {
                    try w.print("layout (location = {d}) in {s} v_{s};\n", .{ vi.location, @tagName(vi.attr_type), vi.name });
                }
                try w.writeAll("#define vf out\n");
                try w.writeAll("#define STAGE_VERTEX\n");
            }
            if (stage == .fragment) {
                for (defs.frag_outputs) |fo| {
                    try w.print("layout (location = {d}) out {s} f_{s};\n", .{ fo.location, @tagName(fo.attr_type), fo.name });
                }
                try w.writeAll("#define vf in\n");
                try w.writeAll("#define STAGE_FRAGMENT\n");
            }
            for (shader_defs.source_modules) |module| {
                try w.print("{s}\n", .{module});
            }
            try w.writeAll("#line 1 0\n");
            try w.writeAll(body);
            return source.toOwnedSlice(allocator);
        }

        pub fn setUniform(self: Self, comptime tag: UniformTag, value: UniformValue(tag)) void {
            const u = defs.uniforms[@intFromEnum(tag)];
            if (u.array_len == null) {
                self.program.setUniform(self.uniform_locations[@intFromEnum(tag)], u.uniform_type, value);
            } else {
                self.program.setUniformArray(self.uniform_locations[@intFromEnum(tag)], u.uniform_type, value);
            }
        }

        pub fn setSampler(self: Self, comptime tag: SamplerTag, value: u32) void {
            self.program.setUniform(self.sampler_locations[@intFromEnum(tag)], .int, @as(c_int, @intCast(value)));
        }

        pub fn use(self: Self) void {
            self.program.use();
        }
    };
}
