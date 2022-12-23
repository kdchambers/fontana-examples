// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");
const fontana = @import("fontana");
const app = @import("app.zig");
const graphics = @import("graphics.zig");
const freetype = @import("freetype");
const otf = fontana.otf;
const geometry = fontana.geometry;

const application_name = "fontana tester";
const asset_path_font = "assets/Roboto-Medium.ttf";

const Atlas = fontana.Atlas;
const PixelType = fontana.graphics.RGBA(f32);

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

fn FontInterface(comptime capacity: usize) type {
    const GlyphInfo = struct {
        bounding_box: geometry.BoundingBox(i32),
        advance_x: u16,
        leftside_bearing: i16,
        decent: i16,
    };

    return struct {
        font: *otf.FontInfo,
        atlas: *Atlas,
        codepoints: []const u8,
        atlas_entries: [capacity]geometry.Extent2D(u32),

        pub inline fn textureExtentFromIndex(self: *@This(), codepoint: u8) geometry.Extent2D(u32) {
            const atlas_index = blk: {
                var i: usize = 0;
                while (i < capacity) : (i += 1) {
                    const current_codepoint = self.codepoints[i];
                    if (current_codepoint == codepoint) break :blk i;
                }
                unreachable;
            };
            return self.atlas_entries[atlas_index];
        }

        pub inline fn textureDimensions(self: *@This()) geometry.Dimensions2D(u32) {
            const size = self.atlas.size;
            return .{
                .width = size,
                .height = size,
            };
        }

        pub inline fn glyphIndexFromCodepoint(self: *@This(), codepoint: u8) ?u32 {
            return otf.findGlyphIndex(self.font, codepoint);
        }

        pub inline fn glyphInfoFromIndex(self: *@This(), glyph_index: u32) GlyphInfo {
            var glyph_info: GlyphInfo = undefined;
            glyph_info.bounding_box = otf.calculateGlyphBoundingBox(self.font, glyph_index) catch unreachable;
            glyph_info.leftside_bearing = otf.leftBearingForGlyph(self.font, glyph_index);
            glyph_info.advance_x = otf.advanceXForGlyph(self.font, glyph_index);
            glyph_info.decent = -@intCast(i16, glyph_info.bounding_box.y0);
            return glyph_info;
        }

        pub inline fn scaleForPointSize(self: *@This(), target_point_size: f64) f64 {
            const units_per_em = self.font.units_per_em;
            const ppi = 100;
            return otf.fUnitToPixelScale(target_point_size, ppi, units_per_em);
        }

        pub inline fn kernPairAdvance(self: *@This()) ?i16 {
            // TODO: Implement
            _ = self;
            return null;
        }
    };
}

const atlas_codepoints = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!";
const render_text = "Hello World!";
const point_size: f64 = 18.0; // 24 pixels

var font_interface: FontInterface(atlas_codepoints.len) = undefined;
var text_writer_interface: TextWriterInterface = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    try app.init(allocator, application_name);

    var font = try fontana.otf.loadFromFile(allocator, asset_path_font);
    defer font.deinit(allocator);

    const app_texture = app.getTextureMut();

    const pixel_count = @intCast(usize, app_texture.dimensions.width) * app_texture.dimensions.height;
    std.mem.set(graphics.RGBA(f32), app_texture.pixels[0..pixel_count], .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 });

    var atlas = try fontana.Atlas.init(allocator, app_texture.dimensions.width);
    defer atlas.deinit(allocator);

    font_interface = .{
        .font = &font,
        .atlas = &atlas,
        .codepoints = atlas_codepoints,
        .atlas_entries = undefined,
    };

    const ppi = 100;
    const funit_to_pixel = otf.fUnitToPixelScale(point_size, ppi, font.units_per_em);
    for (atlas_codepoints) |codepoint, codepoint_i| {
        const required_dimensions = try otf.getRequiredDimensions(&font, codepoint, funit_to_pixel);
        font_interface.atlas_entries[codepoint_i] = try atlas.reserve(
            allocator,
            required_dimensions.width,
            required_dimensions.height,
        );
        var pixel_writer = fontana.rasterizer.SubTexturePixelWriter(PixelType){
            .texture_width = app_texture.dimensions.width,
            .pixels = @ptrCast([*]fontana.graphics.RGBA(f32), app_texture.pixels),
            .write_extent = font_interface.atlas_entries[codepoint_i],
        };
        otf.rasterizeGlyph(allocator, pixel_writer, &font, @floatCast(f32, funit_to_pixel), codepoint) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.Unknown,
            };
        };
    }

    text_writer_interface = .{
        .quad_writer = app.faceWriter(),
    };

    const scale_factor = app.scaleFactor();
    try fontana.drawText(
        render_text,
        .{ .x = 0.0, .y = 0.0 },
        .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
        point_size,
        &text_writer_interface,
        &font_interface,
    );

    app.onResize = onResize;

    try app.doLoop();
}

fn onResize(width: f32, height: f32) void {
    std.log.info("Resizing: {d}, {d}", .{ width, height });
    const scale_factor = app.scaleFactor();
    fontana.drawText(
        render_text,
        .{ .x = 0.0, .y = 0.1 },
        .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
        point_size,
        &text_writer_interface,
        &font_interface,
    ) catch |err| {
        std.log.err("Failed to draw text. Error: {}", .{err});
    };
}
