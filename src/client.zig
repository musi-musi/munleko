const std = @import("std");
const window = @import("window");
const gl = @import("gl");

const musileko = @import("musileko.zig");

const Allocator = std.mem.Allocator;
const Session = musileko.Session;
const Window = window.Window;


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    try window.init();
    defer window.deinit();

    var client: Client = undefined;
    try client.init(allocator);
    defer client.deinit();

    try client.run();

}

pub const Client = struct {

    window: Window,
    session: Session,

    pub fn init(self: *Client, allocator: Allocator) !void {
        self.window = Window.init(allocator);
        try self.session.init(
            allocator,
            Session.Callbacks.init(
                self,
                tick,
            ),
        );
    }

    pub fn deinit(self: *Client) void {
        self.window.deinit();
        self.session.deinit();
    }

    pub fn run(self: *Client) !void {
        try self.window.create(.{});
        defer self.window.destroy();
        self.window.makeContextCurrent();
        try gl.init(window.getGlProcAddress);
        gl.viewport(.{self.window.width, self.window.height});
        while (self.window.nextFrame()) {
            for(self.window.events.get(.framebuffer_size)) |size| {
                gl.viewport(size);
                std.log.info("framebuffer {d}x{d}", .{size[0], size[1]});
            }
            for (self.window.events.get(.button_pressed)) |button| {
                std.log.info("{s} pressed", .{@tagName(button)});
            }
            for (self.window.events.get(.button_released)) |button| {
                std.log.info("{s} released", .{@tagName(button)});
            }
        }
    }

    pub fn tick(self: *Client, session: *Session) !void {
        _ = self;
        if (session.tick_count % 100 == 0) {
            std.log.debug("tick {d}", .{ session.tick_count });
        }
    }

};