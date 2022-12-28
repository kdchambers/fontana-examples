// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");
const fontana = @import("fontana");
const app = @import("app.zig");
const graphics = @import("graphics.zig");
const geometry = fontana.geometry;

const application_name = "fontana tester";
const asset_path_font = "assets/Roboto-Medium.ttf";

const TextWriterInterface = struct {
    quad_writer: *app.QuadFaceWriter(graphics.GenericVertex),
    pub fn write(
        self: *@This(),
        screen_extent: fontana.geometry.Extent2D(f32),
        texture_extent: fontana.geometry.Extent2D(f32),
    ) !void {
        (try self.quad_writer.create()).* = graphics.generateTexturedQuad(
            graphics.GenericVertex,
            screen_extent,
            texture_extent,
            .bottom_left,
        );
    }
};

const atlas_codepoints = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!";
const render_text = "Seasons Greetings!";
const point_size: f64 = 18.0; // 24 pixels

var text_writer_interface: TextWriterInterface = undefined;

const Font = fontana.Font(.fontana);
const Pen = Font.Pen;

var pen: Pen = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    try app.init(allocator, application_name);

    const app_texture = app.getTextureMut();

    const pixel_count = @intCast(usize, app_texture.dimensions.width) * app_texture.dimensions.height;
    std.mem.set(graphics.RGBA(f32), app_texture.pixels[0..pixel_count], .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 });

    var font = try Font.loadFromFile(allocator, asset_path_font);
    defer font.deinit(allocator);

    pen = try font.createPen(
        graphics.RGBA(f32),
        allocator,
        .{ .point = point_size },
        100,
        atlas_codepoints,
        app_texture.dimensions.width,
        app_texture.pixels,
    );

    text_writer_interface = .{
        .quad_writer = app.faceWriter(),
    };
    app.onResize = onResize;

    try app.doLoop();
}

fn onResize(width: f32, height: f32) void {
    std.log.info("Resizing: {d}, {d}", .{ width, height });
    const scale_factor = app.scaleFactor();
    pen.write(
        render_text,
        .{ .x = -0.8, .y = 0.0 },
        .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
        &text_writer_interface,
    ) catch |err| {
        std.log.err("Failed to draw text. Error: {}", .{err});
    };
}
