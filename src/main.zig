// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");
const fontana = @import("fontana");
const app = @import("app.zig");
const graphics = @import("graphics.zig");
const geometry = fontana.geometry;
const builtin = @import("builtin");
const build_mode = builtin.mode;
const is_debug = (build_mode == .Debug);

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

const application_name = "fontana tester";
const asset_path_font = "assets/Roboto-Medium.ttf";
const atlas_codepoints = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!";
const render_text = "Seasons Greetings!";
const point_size: f64 = 18.0; // 24 pixels
const font_backend: fontana.Backend = .fontana;
const Font = fontana.Font(font_backend);

var text_writer_interface: TextWriterInterface = undefined;
var pen: Font.Pen = undefined;
var gpa = if (is_debug) std.heap.GeneralPurposeAllocator(.{}){} else {};

pub fn main() !void {
    var allocator = if (is_debug) gpa.allocator() else std.heap.c_allocator;
    defer {
        if (is_debug)
            _ = gpa.deinit();
    }

    try app.init(allocator, application_name);
    const texture = app.getTextureMut();

    const font_setup_start = std.time.nanoTimestamp();
    var font = try Font.loadFromFile(allocator, asset_path_font);
    defer font.deinit(allocator);

    {
        const PixelType = graphics.RGBA(f32);
        const points_per_pixel = 100;
        const font_size = fontana.Size{ .point = point_size };
        pen = try font.createPen(
            PixelType,
            allocator,
            font_size,
            points_per_pixel,
            atlas_codepoints,
            texture.dimensions.width,
            texture.pixels,
        );
    }
    defer pen.deinit(allocator);
    const font_setup_end = std.time.nanoTimestamp();
    const font_setup_duration = @intCast(u64, font_setup_end - font_setup_start);
    std.log.info("Font setup in {} for backend `{s}` in mode `{s}`", .{
        std.fmt.fmtDuration(font_setup_duration),
        @tagName(font_backend),
        @tagName(build_mode),
    });

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
