const std = @import("std");
const gl = @import("gl");

const ls = @import("../ls.zig");

pub const MeshConfig = struct {

    buffers: []const MeshBufferDef,
    index_type: gl.IndexType = .uint,
    primitive_type: gl.PrimitiveType = .triangles,

    pub fn vertexInDefs(comptime self: MeshConfig) []const ls.VertInDef {
        var vert_inputs: []const ls.VertInDef = &.{};
        var location = 0;
        for (self.buffers) |buffer| {
            const T = buffer.data_type;
            for (std.meta.fields(T)) |field| {
                vert_inputs = vert_inputs ++ &[_]ls.VertInDef{
                    ls.defVertIn(
                        location,
                        field.name,
                        gl.GlslPrimitive.fromType(field.field_type)
                    )
                };
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
            inline for (cfg.buffers) |buffer, b| {
                const T = buffer.data_type;
                inline for (std.meta.fields(T)) |field| {
                    array.setAttributeFormat(
                        @intCast(u32, b),
                        a,
                        comptime gl.AttrType.fromType(field.field_type),
                        @offsetOf(buffer.data_type, field.name),
                    );
                    a += 1;
                }
                if (buffer.divisor != 0) {
                    array.setBindingDivisor(@intCast(u32, b), buffer.divisor);
                }
            }
            return Self {
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
