const std = @import("std");

const c = @cImport({
    @cInclude("glad/glad.h");
});

const UInt = c.GLuint;

pub const InitError = error{
    LoadGlProcsFailed,
};

pub fn init(getProcAddress: anytype) InitError!void {
    if (c.gladLoadGLLoader(@as(c.GLADloadproc, @ptrCast(getProcAddress))) == 0) {
        return InitError.LoadGlProcsFailed;
    }
}

pub fn viewport(vp: [2]u32) void {
    c.glViewport(0, 0, @as(c_int, @intCast(vp[0])), @as(c_int, @intCast(vp[1])));
}

fn iptrCast(x: anytype) c_longlong {
    return @as(c_longlong, @intCast(x));
}

fn vptrCast(p: anytype) *const anyopaque {
    return @as(*const anyopaque, @ptrCast(p));
}

pub const Enabled = enum {
    enabled,
    disabled,
};

pub const Capability = enum(UInt) {
    blend = c.GL_BLEND,
    depth_test = c.GL_DEPTH_TEST,
    scissor_test = c.GL_SCISSOR_TEST,
    stencil_test = c.GL_STENCIL_TEST,
    framebuffer_srgb = c.GL_FRAMEBUFFER_SRGB,
    multisample = c.GL_MULTISAMPLE,
    cull_face = c.GL_CULL_FACE,
};

pub fn enable(cap: Capability) void {
    c.glEnable(@intFromEnum(cap));
}

pub fn disable(cap: Capability) void {
    c.glDisable(@intFromEnum(cap));
}

pub fn setEnabled(cap: Capability, enabled: Enabled) void {
    switch (enabled) {
        .enabled => enable(cap),
        .disabled => disable(cap),
    }
}

pub const DepthFunc = enum(c_uint) {
    never = c.GL_NEVER,
    less = c.GL_LESS,
    equal = c.GL_EQUAL,
    lequal = c.GL_LEQUAL,
    greater = c.GL_GREATER,
    not_equal = c.GL_NOTEQUAL,
    gequal = c.GL_GEQUAL,
    always = c.GL_ALWAYS,
};

pub fn setDepthFunction(func: DepthFunc) void {
    c.glDepthFunc(@intFromEnum(func));
}

pub const Name = UInt;

pub const IndexType = enum(c_int) {
    ubyte = c.GL_UNSIGNED_BYTE,
    ushort = c.GL_UNSIGNED_SHORT,
    uint = c.GL_UNSIGNED_INT,

    pub fn Type(comptime self: IndexType) type {
        return switch (self) {
            .ubyte => u8,
            .ushort => u16,
            .uint => u32,
        };
    }
};

pub fn clearColor(color: [4]f32) void {
    c.glClearColor(color[0], color[1], color[2], color[3]);
}

pub const DepthBits = enum {
    float,
    double,

    pub fn Type(comptime self: DepthBits) type {
        return switch (self) {
            .float => f32,
            .double => f64,
        };
    }
};

pub fn clearDepth(comptime bits: DepthBits, depth: bits.Type()) void {
    c.glClearDepth(@as(f64, @floatCast(depth)));
}

pub fn clearStencil(stencil: i32) void {
    c.glClearStencil(stencil);
}

pub const ClearFlags = enum(u32) {
    color = c.GL_COLOR_BUFFER_BIT,
    depth = c.GL_DEPTH_BUFFER_BIT,
    stencil = c.GL_STENCIL_BUFFER_BIT,
    color_depth = c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT,
    depth_stencil = c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT,
    color_stencil = c.GL_COLOR_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT,
    color_depth_stencil = c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT,
};

pub fn clear(flags: ClearFlags) void {
    c.glClear(@intFromEnum(flags));
}

pub fn lineWidth(width: f32) void {
    c.glLineWidth(width);
}

pub const PrimitiveType = enum(c_uint) {
    points = c.GL_POINTS,
    line_strip = c.GL_LINE_STRIP,
    line_loop = c.GL_LINE_LOOP,
    lines = c.GL_LINES,
    triangle_strip = c.GL_TRIANGLE_STRIP,
    triangle_fan = c.GL_TRIANGLE_FAN,
    triangles = c.GL_TRIANGLES,
};

pub fn drawElements(primitive_type: PrimitiveType, index_count: usize, comptime index_type: IndexType) void {
    c.glDrawElements(@intFromEnum(primitive_type), @as(c_int, @intCast(index_count)), @intFromEnum(index_type), null);
}

pub fn drawElementsInstanced(primitive_type: PrimitiveType, index_count: usize, comptime index_type: IndexType, instance_count: usize) void {
    c.glDrawElementsInstanced(
        @intFromEnum(primitive_type),
        @as(c_int, @intCast(index_count)),
        @intFromEnum(index_type),
        null,
        @as(c_int, @intCast(instance_count)),
    );
}

pub const BufferUsage = enum(UInt) {
    stream_draw = c.GL_STREAM_DRAW,
    stream_read = c.GL_STREAM_READ,
    stream_copy = c.GL_STREAM_COPY,
    static_draw = c.GL_STATIC_DRAW,
    static_read = c.GL_STATIC_READ,
    static_copy = c.GL_STATIC_COPY,
    dynamic_draw = c.GL_DYNAMIC_DRAW,
    dynamic_read = c.GL_DYNAMIC_READ,
    dynamic_copy = c.GL_DYNAMIC_COPY,
};

fn assertIsBuffer(comptime T: type) void {
    if (!@hasDecl(T, "Element") or T != Buffer(T.Element)) {
        @compileError(@typeName(T) ++ " is not a gl.Buffer");
    }
}

pub fn Buffer(comptime T: type) type {
    return struct {
        name: Name = 0,

        pub const Element = T;
        pub const stride = @sizeOf(T);

        const Self = @This();

        pub fn create() Self {
            var self = Self{};
            c.glCreateBuffers(1, &self.name);
            return self;
        }

        pub fn destroy(self: Self) void {
            c.glDeleteBuffers(1, &self.name);
        }

        pub fn alloc(self: Self, size: usize, usage: BufferUsage) void {
            c.glNamedBufferData(self.name, iptrCast(size * stride), null, @intFromEnum(usage));
        }

        pub fn data(self: Self, slice: []const T, usage: BufferUsage) void {
            const ptr = vptrCast(slice.ptr);
            const size = iptrCast(slice.len * stride);
            c.glNamedBufferData(self.name, size, ptr, @intFromEnum(usage));
        }

        pub fn subData(self: Self, slice: []const T, offset: usize) void {
            const ptr = vptrCast(slice.ptr);
            const size = iptrCast(slice.len * stride);
            c.glNamedBufferSubData(self.name, iptrCast(offset * stride), size, ptr);
        }
    };
}

pub const Array = struct {
    name: Name = 0,

    pub fn create() Array {
        var self = Array{};
        c.glCreateVertexArrays(1, &self.name);
        return self;
    }

    pub fn destroy(self: Array) void {
        c.glDeleteVertexArrays(1, &self.name);
    }

    pub fn setAttributeFormat(self: Array, binding: u32, attr: u32, attr_type: AttrType, stride: usize) void {
        c.glEnableVertexArrayAttrib(self.name, attr);
        switch (attr_type.primitive) {
            .half,
            .float,
            => c.glVertexArrayAttribFormat(self.name, @as(UInt, @intCast(attr)), @as(c_int, @intCast(attr_type.len)), @intFromEnum(attr_type.primitive), 0, @as(UInt, @intCast(stride))),
            .double => c.glVertexArrayAttribLFormat(self.name, @as(UInt, @intCast(attr)), @as(c_int, @intCast(attr_type.len)), @intFromEnum(attr_type.primitive), @as(UInt, @intCast(stride))),
            else => c.glVertexArrayAttribIFormat(self.name, @as(UInt, @intCast(attr)), @as(c_int, @intCast(attr_type.len)), @intFromEnum(attr_type.primitive), @as(UInt, @intCast(stride))),
        }
        c.glVertexArrayAttribBinding(
            self.name,
            @as(UInt, @intCast(attr)),
            @as(UInt, @intCast(binding)),
        );
    }

    pub fn setBindingDivisor(self: Array, binding: u32, divisor: u32) void {
        c.glVertexArrayBindingDivisor(
            self.name,
            @as(UInt, @intCast(binding)),
            @as(UInt, @intCast(divisor)),
        );
    }

    pub fn setVertexBuffer(self: Array, binding: u32, buffer: anytype, offset: u32) void {
        const B = @TypeOf(buffer);
        comptime assertIsBuffer(B);
        c.glVertexArrayVertexBuffer(
            self.name,
            @as(UInt, @intCast(binding)),
            buffer.name,
            @as(c.GLintptr, @intCast(offset)),
            @as(c_int, @intCast(B.stride)),
        );
    }

    pub fn setIndexBuffer(self: Array, buffer: anytype) void {
        comptime assertIsBuffer(@TypeOf(buffer));
        c.glVertexArrayElementBuffer(self.name, buffer.name);
    }

    pub fn bind(self: Array) void {
        c.glBindVertexArray(self.name);
    }
};

/// pair of a gl primitive type enum and length (1-4 inc.)
/// attribute types are defined in zig as
/// `prim` or `[n]prim`, where prim is a numerical primitive gl supports and n is between 1 and 4 inclusive
/// ex: `float = f32`
/// ex: `vec3i = [3]i32`
/// TODO: support larger attributes like matrices
pub const AttrType = struct {
    primitive: Primitive,
    len: usize,

    /// mapping between zig types and gl enum values for supported vertex attribute primitives
    pub const Primitive = enum(UInt) {
        byte = c.GL_BYTE,
        ubyte = c.GL_UNSIGNED_BYTE,
        short = c.GL_SHORT,
        ushort = c.GL_UNSIGNED_SHORT,
        int = c.GL_INT,
        uint = c.GL_UNSIGNED_INT,
        half = c.GL_HALF_FLOAT,
        float = c.GL_FLOAT,
        double = c.GL_DOUBLE,

        pub fn ToType(comptime self: Primitive) type {
            return switch (self) {
                .byte => i8,
                .ubyte => u8,
                .short => i16,
                .ushort => u16,
                .int => i32,
                .uint => u32,
                .half => f16,
                .float => f32,
                .double => f64,
            };
        }

        pub fn fromType(comptime T: type) Primitive {
            return switch (T) {
                i8 => .byte,
                u8 => .ubyte,
                i16 => .short,
                u16 => .ushort,
                i32 => .int,
                u32 => .uint,
                f16 => .half,
                f32 => .float,
                f64 => .double,
                else => @compileError("unsupported attrib primitive " ++ @typeName(T)),
            };
        }
    };

    pub fn fromType(comptime Attribute: type) AttrType {
        switch (@typeInfo(Attribute)) {
            .Int, .Float => {
                return AttrType{
                    .primitive = Primitive.fromType(Attribute),
                    .len = 1,
                };
            },
            .Array => |array| {
                const len = array.len;
                switch (len) {
                    1, 2, 3, 4 => {
                        return AttrType{ .primitive = Primitive.fromType(array.child), .len = len };
                    },
                    else => @compileError("only vectors up to 4d are supported"),
                }
            },
            else => @compileError("only primitives or vectors of primitives (arrays 1-4 long) supported"),
        }
    }
};

pub const StageType = enum(UInt) {
    vertex = c.GL_VERTEX_SHADER,
    fragment = c.GL_FRAGMENT_SHADER,
};

fn assertIsStage(comptime T: type) void {
    if (!@hasDecl(T, "stage_type") or T != Stage(T.stage_type)) {
        @compileError(@typeName(T) ++ " is not a gl.Stage");
    }
}

pub const VertexStage = Stage(.vertex);
pub const FragmentStage = Stage(.fragment);

pub fn Stage(comptime stage: StageType) type {
    return struct {
        name: Name = 0,

        pub const stage_type = stage;

        const Self = @This();

        pub fn create() Self {
            return .{
                .name = c.glCreateShader(@intFromEnum(stage_type)),
            };
        }

        pub fn destroy(self: Self) void {
            c.glDeleteShader(self.name);
        }

        pub fn source(self: Self, text: []const u8) void {
            const len = @as(c_int, @intCast(text.len));
            c.glShaderSource(self.name, 1, &text.ptr, &len);
        }

        pub fn compile(self: Self) Program.Error!void {
            c.glCompileShader(self.name);
            var success: c_int = undefined;
            c.glGetShaderiv(self.name, c.GL_COMPILE_STATUS, &success);
            if (success == 0) {
                const max_msg_size = 512;
                var msg: [512]u8 = undefined;
                c.glGetShaderInfoLog(self.name, max_msg_size, null, &msg);
                std.log.err("failed to compile {s} shader:\n{s}", .{ @tagName(stage_type), msg });
                return Program.Error.CompilationFailed;
            }
        }
    };
}

pub const Program = struct {
    name: Name = 0,

    pub const Error = error{
        CompilationFailed,
        LinkingFailed,
    };

    pub fn create() Program {
        return .{
            .name = c.glCreateProgram(),
        };
    }

    pub fn destroy(self: Program) void {
        c.glDeleteProgram(self.name);
    }

    pub fn attach(self: Program, stage: anytype) void {
        const S = @TypeOf(stage);
        comptime assertIsStage(S);
        c.glAttachShader(self.name, stage.name);
    }

    pub fn link(self: Program) Error!void {
        c.glLinkProgram(self.name);
        var success: c_int = undefined;
        c.glGetProgramiv(self.name, c.GL_LINK_STATUS, &success);
        if (success == 0) {
            const max_msg_size = 512;
            var msg: [512]u8 = undefined;
            c.glGetProgramInfoLog(self.name, max_msg_size, null, &msg);
            std.log.err("failed to link shader program:\n{s}", .{msg});
            return Error.LinkingFailed;
        }
    }

    pub fn use(self: Program) void {
        c.glUseProgram(self.name);
    }

    pub fn getUniformLocation(self: Program, uniform_name: [:0]const u8) UniformLocation {
        return c.glGetUniformLocation(
            self.name,
            uniform_name.ptr,
        );
    }

    pub fn setUniform(
        self: Program,
        uniform: UniformLocation,
        comptime uniform_type: GlslPrimitive,
        value: uniform_type.Type(),
    ) void {
        const v = [1]uniform_type.Type(){value};
        self.setUniformArray(uniform, uniform_type, &v);
    }

    pub fn setUniformArray(
        self: Program,
        uniform: UniformLocation,
        comptime uniform_type: GlslPrimitive,
        value: []const uniform_type.Type(),
    ) void {
        const count = @as(c_int, @intCast(value.len));
        const ptr = @as(*const uniform_type.Element(), @ptrCast(value.ptr));
        const transpose = 0;
        switch (uniform_type) {
            .float => c.glProgramUniform1fv(self.name, uniform, count, ptr),
            .vec2 => c.glProgramUniform2fv(self.name, uniform, count, ptr),
            .vec3 => c.glProgramUniform3fv(self.name, uniform, count, ptr),
            .vec4 => c.glProgramUniform4fv(self.name, uniform, count, ptr),

            .mat2 => c.glProgramUniformMatrix2fv(self.name, uniform, count, transpose, ptr),
            .mat3 => c.glProgramUniformMatrix3fv(self.name, uniform, count, transpose, ptr),
            .mat4 => c.glProgramUniformMatrix4fv(self.name, uniform, count, transpose, ptr),

            .int => c.glProgramUniform1iv(self.name, uniform, count, ptr),
            .ivec2 => c.glProgramUniform2iv(self.name, uniform, count, ptr),
            .ivec3 => c.glProgramUniform3iv(self.name, uniform, count, ptr),
            .ivec4 => c.glProgramUniform4iv(self.name, uniform, count, ptr),

            .uint => c.glProgramUniform1uiv(self.name, uniform, count, ptr),
            .uivec2 => c.glProgramUniform2uiv(self.name, uniform, count, ptr),
            .uivec3 => c.glProgramUniform3uiv(self.name, uniform, count, ptr),
            .uivec4 => c.glProgramUniform4uiv(self.name, uniform, count, ptr),
        }
    }
};

pub const UniformLocation = c_int;

pub const GlslPrimitive = enum(u8) {
    float,
    vec2,
    vec3,
    vec4,

    int,
    ivec2,
    ivec3,
    ivec4,

    uint,
    uivec2,
    uivec3,
    uivec4,

    mat2,
    mat3,
    mat4,

    pub fn fromType(comptime T: type) GlslPrimitive {
        comptime {
            for (std.enums.values(GlslPrimitive)) |t| {
                if (T == t.Type()) {
                    return t;
                }
            }
            @compileError(@typeName(T) ++ " us not a gl.GlslPrimitive");
        }
    }

    /// get the zig type used to represent this glsl type
    pub fn Type(comptime self: GlslPrimitive) type {
        return switch (self) {
            .float => f32,
            .vec2 => [2]f32,
            .vec3 => [3]f32,
            .vec4 => [4]f32,
            .mat2 => [2][2]f32,
            .mat3 => [3][3]f32,
            .mat4 => [4][4]f32,

            .int => i32,
            .ivec2 => [2]i32,
            .ivec3 => [3]i32,
            .ivec4 => [4]i32,

            .uint => u32,
            .uivec2 => [2]u32,
            .uivec3 => [3]u32,
            .uivec4 => [4]u32,
        };
    }

    /// get the zig type used to represent the underlying element
    /// eg vec4, mat3, float -> f32
    pub fn Element(comptime self: GlslPrimitive) type {
        return switch (self) {
            .float,
            .vec2,
            .vec3,
            .vec4,
            .mat2,
            .mat3,
            .mat4,
            => f32,

            .int,
            .ivec2,
            .ivec3,
            .ivec4,
            => i32,

            .uint,
            .uivec2,
            .uivec3,
            .uivec4,
            => u32,
        };
    }
};

pub fn TextureRgba8(comptime target_: TextureTarget) type {
    return Texture(target_, .{
        .channels = .rgba,
        .component = .u8norm,
    });
}

pub fn Texture(comptime target_: TextureTarget, comptime format_: PixelFormat) type {
    return struct {
        name: Name,

        pub const target = target_;
        pub const format = format_;

        pub const Pixel = format.Pixel();

        const Self = @This();

        pub fn create() Self {
            var name: Name = undefined;
            c.glCreateTextures(@intFromEnum(target), 1, &name);
            return .{
                .name = name,
            };
        }

        pub fn destroy(self: Self) void {
            c.glDeleteTextures(1, &self.name);
        }

        pub fn bind(self: Self, unit: i32) void {
            c.glBindTextureUnit(@as(c_uint, @intCast(unit)), self.name);
        }

        pub fn setFilter(self: Self, min_filter: TextureFilter, mag_filter: TextureFilter) void {
            c.glTextureParameteri(self.name, c.GL_TEXTURE_MIN_FILTER, @as(c_int, @intCast(@intFromEnum(min_filter))));
            c.glTextureParameteri(self.name, c.GL_TEXTURE_MAG_FILTER, @as(c_int, @intCast(@intFromEnum(mag_filter))));
        }

        pub usingnamespace switch (target) {
            .texture_2d => struct {
                pub fn alloc(self: Self, width: usize, height: usize) void {
                    const w = @as(c_int, @intCast(width));
                    const h = @as(c_int, @intCast(height));
                    c.glTextureStorage2D(self.name, 1, comptime format.sizedFormat(), w, h);
                }

                pub fn upload(self: Self, width: usize, height: usize, data: []const Pixel) void {
                    const w = @as(c_int, @intCast(width));
                    const h = @as(c_int, @intCast(height));
                    const x: c_int = 0;
                    const y: c_int = 0;
                    const mip: c_int = 0;
                    const channels = format.channels.glType();
                    const component = format.component.glType();
                    c.glTextureSubImage2D(self.name, mip, x, y, w, h, channels, component, @as(*const anyopaque, @ptrCast(data.ptr)));
                }

                /// allocate for framebuffer usage
                pub fn allocFramebuffer(self: Self, width: usize, height: usize) void {
                    // const w = @intCast(c_int, width);
                    // const h = @intCast(c_int, height);
                    // const mip: c_int = 0;
                    // const channels = format.channels.glType();
                    // const component = format.component.glType();
                    // c.glTextureImage2D(self.name, mip, comptime format.sizedFormat(), w, h, 0, channels, component, null);
                    self.alloc(width, height);
                }
            },
            .array_2d => struct {
                pub fn alloc(self: Self, width: usize, height: usize, count: usize) void {
                    const w = @as(c_int, @intCast(width));
                    const h = @as(c_int, @intCast(height));
                    const cnt = @as(c_int, @intCast(count));
                    c.glTextureStorage3D(self.name, 1, comptime format.sizedFormat(), w, h, cnt);
                }

                pub fn upload(self: Self, width: usize, height: usize, index: usize, data: []const Pixel) void {
                    const w = @as(c_int, @intCast(width));
                    const h = @as(c_int, @intCast(height));
                    const i = @as(c_int, @intCast(index));
                    const x: c_int = 0;
                    const y: c_int = 0;
                    const mip: c_int = 0;
                    const channels = format.channels.glType();
                    const component = format.component.glType();
                    c.glTextureSubImage3D(self.name, mip, x, y, i, w, h, 1, channels, component, @as(*const anyopaque, @ptrCast(data.ptr)));
                }
            },
        };
    };
}

pub const TextureTarget = enum(UInt) {
    texture_2d = c.GL_TEXTURE_2D,
    array_2d = c.GL_TEXTURE_2D_ARRAY,

    pub fn isArray(self: TextureTarget) bool {
        return switch (self) {
            .texture_2d => false,
            .array_2d => true,
        };
    }

    pub fn dimensions(self: TextureTarget) u32 {
        return switch (self) {
            .texture_2d => 2,
            .array_2d => 3,
        };
    }
};

pub const TextureFilter = enum(UInt) {
    nearest = c.GL_NEAREST,
    linear = c.GL_LINEAR,
};

pub const PixelFormat = struct {
    channels: PixelChannels = .rgba,
    component: PixelComponent = .u8norm,

    pub fn Pixel(comptime self: PixelFormat) type {
        return [self.channels.dimensions()]self.component.Type();
    }

    pub fn sizedFormat(comptime self: PixelFormat) c_uint {
        return switch (self.channels) {
            .r => switch (self.component) {
                .u8norm => @as(c_uint, c.GL_R8),
                .i8norm => @as(c_uint, c.GL_R8_SNORM),
                .u8 => @as(c_uint, c.GL_R8UI),
                .i8 => @as(c_uint, c.GL_R8I),
                .u16norm => @as(c_uint, c.GL_R16),
                .i16norm => @as(c_uint, c.GL_R16_SNORM),
                .u16 => @as(c_uint, c.GL_R16UI),
                .i16 => @as(c_uint, c.GL_R16I),
                .u32 => @as(c_uint, c.GL_R32UI),
                .i32 => @as(c_uint, c.GL_R32I),
                .f32 => @as(c_uint, c.GL_R32F),
            },
            .rg => switch (self.component) {
                .u8norm => @as(c_uint, c.GL_RG8),
                .i8norm => @as(c_uint, c.GL_RG8_SNORM),
                .u8 => @as(c_uint, c.GL_RG8UI),
                .i8 => @as(c_uint, c.GL_RG8I),
                .u16norm => @as(c_uint, c.GL_RG16),
                .i16norm => @as(c_uint, c.GL_RG16_SNORM),
                .u16 => @as(c_uint, c.GL_RG16UI),
                .i16 => @as(c_uint, c.GL_RG16I),
                .u32 => @as(c_uint, c.GL_RG32UI),
                .i32 => @as(c_uint, c.GL_RG32I),
                .f32 => @as(c_uint, c.GL_RG32F),
            },
            .rgb => switch (self.component) {
                .u8norm => @as(c_uint, c.GL_RGB8),
                .i8norm => @as(c_uint, c.GL_RGB8_SNORM),
                .u8 => @as(c_uint, c.GL_RGB8UI),
                .i8 => @as(c_uint, c.GL_RGB8I),
                .u16norm => @as(c_uint, c.GL_RGB16),
                .i16norm => @as(c_uint, c.GL_RGB16_SNORM),
                .u16 => @as(c_uint, c.GL_RGB16UI),
                .i16 => @as(c_uint, c.GL_RGB16I),
                .u32 => @as(c_uint, c.GL_RGB32UI),
                .i32 => @as(c_uint, c.GL_RGB32I),
                .f32 => @as(c_uint, c.GL_RGB32F),
            },
            .srgb => switch (self.component) {
                .u8norm => @as(c_uint, c.GL_SRGB8),
                else => @compileError("srgb is only valid for byte bit depth"),
            },
            .rgba => switch (self.component) {
                .u8norm => @as(c_uint, c.GL_RGBA8),
                .i8norm => @as(c_uint, c.GL_RGBA8_SNORM),
                .u8 => @as(c_uint, c.GL_RGBA8UI),
                .i8 => @as(c_uint, c.GL_RGBA8I),
                .u16norm => @as(c_uint, c.GL_RGBA16),
                .i16norm => @as(c_uint, c.GL_RGBA16_SNORM),
                .u16 => @as(c_uint, c.GL_RGBA16UI),
                .i16 => @as(c_uint, c.GL_RGBA16I),
                .u32 => @as(c_uint, c.GL_RGBA32UI),
                .i32 => @as(c_uint, c.GL_RGBA32I),
                .f32 => @as(c_uint, c.GL_RGBA32F),
            },
            .srgb_alpha => switch (self.component) {
                .u8norm => @as(c_uint, c.GL_SRGB8_ALPHA8),
                else => @compileError("srgb_alpha is only valid for byte bit depth"),
            },
            .depth => switch (self.component) {
                .u16 => @as(c_uint, c.GL_DEPTH_COMPONENT16),
                .u32 => @as(c_uint, c.GL_DEPTH_COMPONENT32),
                .f32 => @as(c_uint, c.GL_DEPTH_COMPONENT32F),
                else => @compileError("unsupported depth format"),
            },
        };
    }
};

pub const PixelChannels = enum(c_uint) {
    r,
    rg,
    rgb,
    srgb,
    rgba,
    srgb_alpha,
    depth,

    pub fn fromDimensions(dims: u32, srgb: bool) PixelChannels {
        return if (!srgb) {
            switch (dims) {
                1 => .r,
                2 => .rg,
                3 => .rgb,
                4 => .rgba,
                else => .rgba,
            }
        } else {
            switch (dims) {
                1 => @compileError("srgb is not supported for channel count 1"),
                2 => @compileError("srgb is not supported for channel count 2"),
                3 => .srgb,
                4 => .srgb_alpha,
                else => .srgb_alpha,
            }
        };
    }

    pub fn dimensions(self: PixelChannels) u32 {
        return switch (self) {
            .r => 1,
            .rg => 2,
            .rgb => 3,
            .srgb => 3,
            .rgba => 4,
            .srgb_alpha => 4,
            .depth => 1,
        };
    }

    pub fn glType(comptime self: PixelChannels) c_uint {
        return switch (self) {
            .r => c.GL_RED,
            .rg => c.GL_RG,
            .rgb => c.GL_RGB,
            .srgb => c.GL_RGB,
            .rgba => c.GL_RGBA,
            .srgb_alpha => c.GL_RGBA,
            .depth => c.GL_DEPTH_COMPONENT,
        };
    }
};

pub const PixelComponent = enum(c_uint) {
    u8norm,
    i8norm,
    u8,
    i8,
    u16,
    i16,
    u16norm,
    i16norm,
    u32,
    i32,
    f32,

    pub fn Type(comptime self: PixelComponent) type {
        return switch (self) {
            .u8norm => u8,
            .i8norm => i8,
            .u8 => u8,
            .i8 => i8,
            .u16norm => u16,
            .i16norm => i16,
            .u16 => u16,
            .i16 => i16,
            .u32 => u32,
            .i32 => i32,
            .f32 => f32,
        };
    }

    pub fn glType(comptime self: PixelComponent) c_uint {
        return switch (self) {
            .u8norm => c.GL_UNSIGNED_BYTE,
            .i8norm => c.GL_BYTE,
            .u8 => c.GL_UNSIGNED_BYTE,
            .i8 => c.GL_BYTE,
            .u16norm => c.GL_UNSIGNED_SHORT,
            .i16norm => c.GL_SHORT,
            .u16 => c.GL_UNSIGNED_SHORT,
            .i16 => c.GL_SHORT,
            .u32 => c.GL_UNSIGNED_INT,
            .i32 => c.GL_INT,
            .f32 => c.GL_FLOAT,
        };
    }
};
