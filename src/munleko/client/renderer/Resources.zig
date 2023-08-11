const std = @import("std");
const util = @import("util");
const nm = @import("nm");
const gl = @import("gl");

const Resources = @This();

const Client = @import("../../Client.zig");
const Engine = @import("../../Engine.zig");

const Session = Engine.Session;

const Allocator = std.mem.Allocator;

const leko_mesh = @import("leko_mesh.zig");
const LekoMaterialTable = leko_mesh.LekoMaterialTable;

allocator: Allocator,
leko_material: LekoMaterialResources,

pub fn create(allocator: Allocator) !*Resources {
    const self = try allocator.create(Resources);
    errdefer allocator.destroy(self);
    self.allocator = allocator;
    try self.leko_material.init(allocator);
    return self;
}

pub fn destroy(self: *Resources) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.leko_material.deinit();
}

pub fn applyAssets(self: *Resources, assets: *Engine.Assets) !void {
    try self.leko_material.applyAssets(assets);
}

pub const LekoTextureAtlas = gl.TextureRgba8(.array_2d);

pub const LekoMaterialResources = struct {
    texture_atlas: LekoTextureAtlas,
    uv_scale: f32 = 1,
    material_table: LekoMaterialTable,

    pub fn init(self: *LekoMaterialResources, allocator: Allocator) !void {
        try self.material_table.init(allocator);
        errdefer self.material_table.deinit();
        self.texture_atlas = LekoTextureAtlas.create();
        errdefer self.texture_atlas.destroy();
        self.texture_atlas.setFilter(.nearest, .nearest);
        self.uv_scale = 1;
    }

    pub fn deinit(self: *LekoMaterialResources) void {
        self.texture_atlas.destroy();
        self.material_table.deinit();
    }

    pub fn applyAssets(self: *LekoMaterialResources, assets: *Engine.Assets) !void {
        const texture_size = assets.leko_texture_size;
        const texture_count = assets.leko_texture_table.map.count();
        self.texture_atlas.alloc(texture_size, texture_size, texture_count);
        var iter = assets.leko_texture_table.map.valueIterator();
        while (iter.next()) |texture| {
            self.texture_atlas.upload(texture_size, texture_size, texture.index, texture.pixels);
        }
        try self.material_table.addMaterialsFromLekoAssets(assets);
        self.uv_scale = @as(f32, @floatFromInt(assets.leko_pixels_per_unit)) / @as(f32, @floatFromInt(assets.leko_texture_size));
    }
};
