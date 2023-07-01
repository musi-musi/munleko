const std = @import("std");
const nm = @import("nm");
const gl = @import("gl");
const ls = @import("ls");

const Scene = @import("Scene.zig");

const SelectionBox = @This();

pub const Vertex = struct {
    position: [3]f32,
};

pub const VertexBuffer = gl.Buffer(Vertex);
pub const IndexBuffer = Mesh.IndexBuffer;

pub const Mesh = ls.Mesh(.{
    .buffers = &.{ls.defVertexBuffer(Vertex)},
    .primitive_type = .lines,
});

pub const Shader = ls.Shader(.{
    .vert_inputs = Mesh.vertex_in_defs,
    .uniforms = &.{
        ls.defUniform("view", .mat4),
        ls.defUniform("proj", .mat4),
        ls.defUniform("position", .vec3),
        ls.defUniform("size", .vec3),
        ls.defUniform("padding", .float),
        ls.defUniform("color", .vec3),
    },
});

shader: Shader,
mesh: Mesh,
vertices: VertexBuffer,
indices: IndexBuffer,

pub fn init() !SelectionBox {
    var self: SelectionBox = undefined;
    self.shader = try Shader.create(.{}, @embedFile("selection_box.glsl"));
    self.mesh = Mesh.create();
    self.vertices = VertexBuffer.create();
    self.indices = IndexBuffer.create();
    self.vertices.data(&.{
        .{ .position = .{ 0, 0, 0 } },
        .{ .position = .{ 0, 0, 1 } },
        .{ .position = .{ 0, 1, 0 } },
        .{ .position = .{ 0, 1, 1 } },
        .{ .position = .{ 1, 0, 0 } },
        .{ .position = .{ 1, 0, 1 } },
        .{ .position = .{ 1, 1, 0 } },
        .{ .position = .{ 1, 1, 1 } },
    }, .static_draw);
    // zig fmt: off
    self.indices.data(&.{
        0, 1, 2, 3, 4, 5, 6, 7,
        0, 2, 1, 3, 4, 6, 5, 7,
        0, 4, 1, 5, 2, 6, 3, 7,
    }, .static_draw);
    // zig fmt: on
    self.mesh.setBuffer(0, self.vertices);
    self.mesh.setIndexBuffer(self.indices);
    return self;
}

pub fn deinit(self: SelectionBox) void {
    self.shader.destroy();
    self.mesh.destroy();
    self.vertices.destroy();
    self.indices.destroy();
}

pub fn setPadding(self: SelectionBox, padding: f32) void {
    self.shader.setUniform(.padding, padding);
}

pub fn setColor(self: SelectionBox, color: [3]f32) void {
    self.shader.setUniform(.color, color);
}

pub fn setCamera(self: SelectionBox, camera: Scene.Camera) void {
    self.shader.setUniform(.view, camera.view_matrix.v);
    self.shader.setUniform(.proj, camera.projection_matrix.v);
}

pub fn draw(self: SelectionBox, position: [3]f32, size: [3]f32) void {
    // gl.lineWidth(1.5);
    self.shader.use();
    self.shader.setUniform(.position, position);
    self.shader.setUniform(.size, size);
    self.mesh.bind();
    self.mesh.drawAssumeBound(24);
}
