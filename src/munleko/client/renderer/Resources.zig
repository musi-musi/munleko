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
leko_texture_atlas: LekoTextureAtlas,
leko_material_table: LekoMaterialTable,
leko_uv_scale: f32 = 1,

pub fn create(allocator: Allocator) !*Resources {
    const self = try allocator.create(Resources);
    errdefer allocator.destroy(self);
    const leko_texture_atlas = LekoTextureAtlas.create();
    errdefer leko_texture_atlas.destroy();
    leko_texture_atlas.setFilter(.nearest, .nearest);
    self.* = .{
        .allocator = allocator,
        .leko_texture_atlas = leko_texture_atlas,
        .leko_material_table = undefined,
    };
    try self.leko_material_table.init(allocator);
    errdefer self.leko_material_table.deinit();
    return self;
}

pub fn destroy(self: *Resources) void {
    const allocator = self.allocator;
    defer allocator.destroy(self);
    self.leko_texture_atlas.destroy();
    self.leko_material_table.deinit();
}

pub fn applyAssets(self: *Resources, assets: *Engine.Assets) !void {
    const texture_size = assets.leko_texture_size;
    const texture_count = assets.leko_texture_table.map.count();
    self.leko_texture_atlas.alloc(texture_size, texture_size, texture_count);
    var iter = assets.leko_texture_table.map.valueIterator();
    while (iter.next()) |texture| {
        self.leko_texture_atlas.upload(texture_size, texture_size, texture.index, texture.pixels);
    }
    try self.leko_material_table.addMaterialsFromLekoAssets(assets);
    self.leko_uv_scale = @as(f32, @floatFromInt(assets.leko_pixels_per_unit)) / @as(f32, @floatFromInt(assets.leko_texture_size));
}

pub const LekoTextureAtlas = gl.TextureRgba8(.array_2d);
