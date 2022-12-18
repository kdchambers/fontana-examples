// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");
const fontana = @import("fontana");
const app = @import("app.zig");
const graphics = @import("graphics.zig");

const application_name = "fontana tester";
const asset_path_font = "assets/Roboto-Medium.ttf";

const Atlas = fontana.Atlas(.{
    .pixel_format = .rgba_f32,
    .encoding = .ascii,
});

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

var text_writer_interface: TextWriterInterface = undefined;
var font_atlas: Atlas = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    try app.init(allocator, application_name);

    //
    // Generate Glyph atlas + write to texture
    //
    var font = try fontana.otf.loadFromFile(allocator, asset_path_font);
    defer font.deinit(allocator);

    const app_texture = app.getTextureMut();

    const codepoints = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
    try font_atlas.init(allocator, &font, codepoints, 20, @ptrCast([*]fontana.graphics.RGBA(f32), app_texture.pixels), .{
        .width = app_texture.dimensions.width,
        .height = app_texture.dimensions.height,
    });
    defer font_atlas.deinit(allocator);

    text_writer_interface = TextWriterInterface{
        .quad_writer = app.faceWriter(),
    };

    app.onResize = onResize;

    try app.doLoop();
}

fn onResize(width: f32, height: f32) void {
    const scale_factor = fontana.geometry.Scale2D(f32){
        .vertical = 2.0 / height,
        .horizontal = 2.0 / width,
    };
    font_atlas.drawText(&text_writer_interface, "Hello!", .{ .x = 0.0, .y = 0.0 }, scale_factor) catch |err| {
        std.log.warn("Failed to draw text. Error: {}", .{err});
    };
}
