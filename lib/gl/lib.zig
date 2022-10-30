const std = @import("std");

const c = @cImport({
    @cInclude("glad/glad.h");
});

const UInt = c.GLuint;

pub const InitError = error {
    LoadGlProcsFailed,
};

pub fn init(getProcAddress: anytype) InitError!void {
    if (c.gladLoadGLLoader(@ptrCast(c.GLADloadproc, getProcAddress)) == 0) {
        return InitError.LoadGlProcsFailed;
    }
}

pub fn viewport(vp: [2]u32) void {
    c.glViewport(0, 0, @intCast(c_int, vp[0]), @intCast(c_int, vp[1]));
}

fn iptrCast(x: anytype) c_longlong {
    return @intCast(c_longlong, x);
}

fn vptrCast(p: anytype) *const anyopaque {
    return @ptrCast(*const anyopaque, p);
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
    c.glEnable(@enumToInt(cap));
}

pub fn disable(cap: Capability) void {
    c.glDisable(@enumToInt(cap));
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
    c.glDepthFunc(@enumToInt(func));
}

pub const Name = UInt;

pub const IndexType = enum(c_int) {
    ubyte = c.GL_UNSIGNED_BYTE,
    ushort = c.GL_UNSIGNED_SHORT,
    uint = c.GL_UNSIGNED_INT,

    pub fn Type(comptime self: IndexType) type {
        return switch(self) {
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
        return switch(self) {
            .float => f32,
            .double => f64,
        };
    }

};

pub fn clearDepth(comptime bits: DepthBits, depth: bits.Type()) void {
    c.glClearDepth(@floatCast(f64, depth));
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
    c.glClear(@enumToInt(flags));
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
    c.glDrawElements(@enumToInt(primitive_type), @intCast(c_int, index_count), @enumToInt(index_type), null);
}

pub fn drawElementsInstanced(primitive_type: PrimitiveType, index_count: usize, comptime index_type: IndexType, instance_count: usize) void {
    c.glDrawElementsInstanced(
        @enumToInt(primitive_type),
        @intCast(c_int, index_count),
        @enumToInt(index_type),
        null,
        @intCast(c_int, instance_count),
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
            c.glNamedBufferData(self.name, iptrCast(size * stride), null, @enumToInt(usage));
        }

        pub fn data(self: Self, slice: []const T, usage: BufferUsage) void {
            const ptr = vptrCast(slice.ptr);
            const size = iptrCast(slice.len * stride);
            c.glNamedBufferData(self.name, size, ptr, @enumToInt(usage));
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
            .half, .float, => c.glVertexArrayAttribFormat(
                self.name,
                @intCast(UInt, attr),
                @intCast(c_int, attr_type.len),
                @enumToInt(attr_type.primitive),
                0,
                @intCast(UInt, stride)
            ),
            .double, => c.glVertexArrayAttribLFormat(
                self.name,
                @intCast(UInt, attr),
                @intCast(c_int, attr_type.len),
                @enumToInt(attr_type.primitive),
                @intCast(UInt, stride)
            ),
            else => c.glVertexArrayAttribIFormat(
                self.name,
                @intCast(UInt, attr),
                @intCast(c_int, attr_type.len),
                @enumToInt(attr_type.primitive),
                @intCast(UInt, stride)
            ),
        }
        c.glVertexArrayAttribBinding(
            self.name,
            @intCast(UInt, attr),
            @intCast(UInt, binding),
        );
    }

    pub fn setBindingDivisor(self: Array, binding: u32, divisor: u32) void {
        c.glVertexArrayBindingDivisor(
            self.name,
            @intCast(UInt, binding),
            @intCast(UInt, divisor),
        );
    }

    pub fn setVertexBuffer(self: Array, binding: u32, buffer: anytype, offset: u32) void {
        const B = @TypeOf(buffer);
        comptime assertIsBuffer(B);
        c.glVertexArrayVertexBuffer(
            self.name,
            @intCast(UInt, binding),
            buffer.name,
            @intCast(c.GLintptr, offset),
            @intCast(c_int, B.stride),
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
                return AttrType {
                    .primitive = Primitive.fromType(Attribute),
                    .len = 1,
                };
            },
            .Array => |array| {
                const len = array.len;
                switch (len) {
                    1, 2, 3, 4 => {
                        return AttrType {
                            .primitive = Primitive.fromType(array.child),
                            .len = len
                        };
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
                .name = c.glCreateShader(@enumToInt(stage_type)),
            };
        }

        pub fn destroy(self: Self) void {
            c.glDeleteShader(self.name);
        }

        pub fn source(self: Self, text: []const u8) void {
            const len = @intCast(c_int, text.len);
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
                std.log.err("failed to compile {s} shader:\n{s}", .{ @tagName(stage_type), msg});
                return Program.Error.CompilationFailed;
            }
        }
    };
}

pub const Program = struct {

    name: Name = 0,

    pub const Error = error {
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
        const v = [1]uniform_type.Type(){ value };
        self.setUniformArray(uniform, uniform_type, &v);
    }

    pub fn setUniformArray(
        self: Program,
        uniform: UniformLocation,
        comptime uniform_type: GlslPrimitive,
        value: []const uniform_type.Type(),
    ) void {
        const count = @intCast(c_int, value.len);
        const ptr = @ptrCast(*const uniform_type.Element(), value.ptr);
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
        return switch(self) {
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
        return switch(self) {
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