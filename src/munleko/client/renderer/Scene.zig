const std = @import("std");
const nm = @import("nm");

const Vec3 = nm.Vec3;
const vec3 = nm.vec3;
const Mat4 = nm.Mat4;

const Debug = @import("Debug.zig");

const Scene = @This();

debug: Debug,

directional_light: Vec3 = Vec3.zero,
camera: Camera = .{},

fog_color: Vec3 = vec3(.{ 0.7, 0.7, 0.7 }),
fog_start: f32 = 32,
fog_end: f32 = 100,
fog_power: f32 = 1.5,

pub fn init(self: *Scene) !void {
    self.* = .{
        .debug = try Debug.init(),
    };
}

pub fn deinit(self: *Scene) void {
    self.debug.deinit();
}

pub fn setupDebug(self: *Scene) *Debug {
    self.debug.setView(self.camera.view_matrix);
    self.debug.setProj(self.camera.projection_matrix);
    self.debug.setLight(self.directional_light);
    return &self.debug;
}

pub fn setFogFromMaxDistance(self: *Scene, distance: f32, start_factor: f32, end_factor: f32) void {
    self.fog_start = distance * start_factor;
    self.fog_end = distance * end_factor;
}

const Plane3 = nm.Plane3;
const plane3 = nm.plane3;

pub const Camera = struct {
    projection: Projection = .{ .perspective = .{} },

    position: Vec3 = Vec3.zero,
    forward: Vec3 = Vec3.unit(.z),
    up: Vec3 = Vec3.unit(.y),

    view_matrix: Mat4 = Mat4.identity,
    projection_matrix: Mat4 = Mat4.identity,
    frustum: Frustum = undefined,

    pub const Frustum = struct {
        planes: [6]Plane3,
        pub fn doesSphereIntersect(self: Frustum, center: Vec3, radius: f32) bool {
            for (self.planes) |plane| {
                if (plane.pointSignedDistance(center) < -radius) {
                    return false;
                }
            }
            return true;
        }
    };

    pub fn init(projection: Projection, view_matrix: Mat4) Camera {
        var self: Camera = undefined;
        self.setProjection(projection);
        self.setViewMatrix(view_matrix);
        return self;
    }

    pub fn initPerspective(perspective: Projection.Perspective, view_matrix: Mat4) Camera {
        return Camera.init(.{ .perspective = perspective }, view_matrix);
    }
    pub fn initOrthographic(orthographic: Projection.Orthographic, view_matrix: Mat4) Camera {
        return Camera.init(.{ .orthographic = orthographic }, view_matrix);
    }

    pub fn setViewMatrix(self: *Camera, matrix: Mat4) void {
        self.view_matrix = matrix;
        const world_to_view = matrix.invert() orelse unreachable;
        self.position = world_to_view.transformPosition(Vec3.zero);
        self.forward = world_to_view.transformDirection(Vec3.unit(.z));
        self.up = world_to_view.transformDirection(Vec3.unit(.y));
    }

    pub fn setProjection(self: *Camera, projection: Projection) void {
        self.projection = projection;
        self.projection_matrix = projection.toMatrix();
        self.frustum = projection.toFrustum();
    }

    pub fn setProjectionPerspective(self: *Camera, perspective: Projection.Perspective) void {
        self.setProjection(.{ .perspective = perspective });
    }

    pub fn setProjectionOrthographic(self: *Camera, orthographic: Projection.Orthographic) void {
        self.setProjection(.{ .orthographic = orthographic });
    }

    pub fn sphereInInFrustum(self: Camera, center: Vec3, radius: f32) bool {
        const view_position = self.view_matrix.transformPosition(center);
        return self.frustum.doesSphereIntersect(view_position, radius);
    }

    pub const Projection = union(enum) {
        perspective: Perspective,
        orthographic: Orthographic,

        pub const Perspective = struct {
            /// fov in degrees
            fov: f32 = 90,
            near_plane: f32 = 0.001,
            far_plane: f32 = 1000,
            aspect_ratio: f32 = 1,
        };

        pub const Orthographic = struct {
            left: f32 = -1,
            right: f32 = 1,
            bottom: f32 = -1,
            top: f32 = 1,
            near: f32 = -1,
            far: f32 = 1,
        };

        pub fn toMatrix(self: Projection) Mat4 {
            return switch (self) {
                .perspective => |p| nm.transform.createPerspective(
                    std.math.degreesToRadians(f32, p.fov),
                    p.aspect_ratio,
                    p.near_plane,
                    p.far_plane,
                ),
                .orthographic => |o| nm.transform.createOrthogonal(
                    o.left,
                    o.right,
                    o.bottom,
                    o.top,
                    o.near,
                    o.far,
                ),
            };
        }

        pub fn toFrustum(self: Projection) Frustum {
            switch (self) {
                .perspective => |p| {
                    const fov_v = std.math.degreesToRadians(f32, p.fov) / 2;
                    const fov_h = std.math.atan(std.math.tan(fov_v) * p.aspect_ratio);
                    const sin_v = std.math.sin(fov_v);
                    const cos_v = std.math.cos(fov_v);
                    const sin_h = std.math.sin(fov_h);
                    const cos_h = std.math.cos(fov_h);
                    return Frustum{
                        .planes = .{
                            // near
                            plane3(Vec3.unitSigned(.z_pos), p.near_plane),
                            // far
                            plane3(Vec3.unitSigned(.z_neg), -p.far_plane),
                            // left
                            plane3(vec3(.{ cos_h, 0, sin_h }), 0),
                            // right
                            plane3(vec3(.{ -cos_h, 0, sin_h }), 0),
                            // top
                            plane3(vec3(.{ 0, -cos_v, sin_v }), 0),
                            // bottom
                            plane3(vec3(.{ 0, cos_v, sin_v }), 0),
                        },
                    };
                },
                .orthographic => |o| {
                    return Frustum{
                        .planes = .{
                            plane3(Vec3.unitSigned(.x_pos), -o.left),
                            plane3(Vec3.unitSigned(.x_neg), o.right),
                            plane3(Vec3.unitSigned(.y_pos), -o.top),
                            plane3(Vec3.unitSigned(.y_neg), o.bottom),
                            plane3(Vec3.unitSigned(.z_pos), o.near),
                            plane3(Vec3.unitSigned(.z_neg), -o.far),
                        },
                    };
                },
            }
        }
    };
};
