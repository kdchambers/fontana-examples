// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");
const fontana = @import("fontana");
const app = @import("app.zig");
const graphics = @import("graphics.zig");
const freetype = @import("freetype");
const harfbuzz = @import("harfbuzz");
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

fn FontInterfaceFontana(comptime capacity: usize) type {
    const GlyphInfo = struct {
        advance_x: f64,
        leftside_bearing: f64,
        decent: f64,
    };

    return struct {
        font: *otf.FontInfo,
        atlas: *Atlas,
        font_scale: f64,
        codepoints: []const u8,
        atlas_entries: [capacity]geometry.Extent2D(u32),

        pub inline fn setSizePoint(self: *@This(), target_point_size: f64) void {
            const units_per_em = self.font.units_per_em;
            const ppi = 100;
            self.font_scale = otf.fUnitToPixelScale(target_point_size, ppi, units_per_em);
        }

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

        pub inline fn glyphMetricsFromCodepoint(self: *@This(), codepoint: u8) GlyphInfo {
            const glyph_index = otf.findGlyphIndex(self.font, codepoint);
            var glyph_info: GlyphInfo = undefined;
            const bounding_box = otf.calculateGlyphBoundingBox(self.font, glyph_index) catch unreachable;
            glyph_info.leftside_bearing = @intToFloat(f64, otf.leftBearingForGlyph(self.font, glyph_index)) * self.font_scale;
            glyph_info.advance_x = @intToFloat(f64, otf.advanceXForGlyph(self.font, glyph_index)) * self.font_scale;
            glyph_info.decent = -@intToFloat(f64, bounding_box.y0) * self.font_scale;
            return glyph_info;
        }

        pub inline fn kernPairAdvance(self: *@This()) ?f64 {
            // TODO: Implement
            _ = self;
            return null;
        }
    };
}

fn FontInterfaceFreetype(comptime capacity: usize) type {
    const GlyphInfo = struct {
        advance_x: f64,
        leftside_bearing: f64,
        decent: f64,
    };

    return struct {
        face: freetype.Face,
        hb_font: harfbuzz.Font,
        atlas: *Atlas,
        font_scale: f64,
        codepoints: []const u8,
        atlas_entries: [capacity]geometry.Extent2D(u32),

        pub inline fn setSizePoint(self: *@This(), target_point_size: f64) void {
            const ppi = 100;
            self.face.setCharSize(0, @floatToInt(i32, @floor(target_point_size) * 64), ppi, ppi) catch unreachable;
        }

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

        pub inline fn glyphMetricsFromCodepoint(self: *@This(), codepoint: u8) GlyphInfo {
            const harfbuzz_text: [1:0]u8 = .{codepoint};

            var hb_buffer = harfbuzz.Buffer.init().?;
            defer hb_buffer.deinit();

            hb_buffer.addUTF8(&harfbuzz_text, 0, null);
            hb_buffer.guessSegmentProps();

            self.hb_font.shape(hb_buffer, null);
            const hb_positions = hb_buffer.getGlyphPositions().?;

            var glyph_info: GlyphInfo = undefined;

            glyph_info.advance_x = @intToFloat(f64, hb_positions[0].x_advance) / 64.0;

            const glyph_index = self.face.getCharIndex(codepoint).?;
            self.face.loadGlyph(glyph_index, .{}) catch unreachable;

            const glyph = self.face.glyph();
            glyph_info.leftside_bearing = @intToFloat(f64, glyph.bitmapLeft());
            glyph_info.decent = (@intToFloat(f64, -glyph.metrics().horiBearingY) / 64);
            glyph_info.decent += @intToFloat(f64, glyph.metrics().height) / 64;
            return glyph_info;
        }

        pub inline fn kernPairAdvance(self: *@This()) ?f64 {
            // TODO: Implement
            _ = self;
            return null;
        }
    };
}

const atlas_codepoints = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!";
const render_text = "Seasons Greetings!";
const point_size: f64 = 18.0; // 24 pixels

var freetype_font_interface: FontInterfaceFreetype(atlas_codepoints.len) = undefined;
var fontana_font_interface: FontInterfaceFontana(atlas_codepoints.len) = undefined;
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

    //
    // Setup Freetype
    //

    const freetype_library = try freetype.Library.init();
    defer freetype_library.deinit();

    const face = try freetype_library.createFace(asset_path_font, 0);
    try face.setCharSize(0, 18 * 64, 100, 100);
    const hb_font = harfbuzz.Font.fromFreetypeFace(face);

    freetype_font_interface = .{
        .face = face,
        .hb_font = hb_font,
        .atlas = &atlas,
        .codepoints = atlas_codepoints,
        .atlas_entries = undefined,
        .font_scale = undefined,
    };

    for (atlas_codepoints) |codepoint, codepoint_i| {
        try face.loadChar(codepoint, .{ .render = true });
        const bitmap = face.glyph().bitmap();

        const bitmap_height = bitmap.rows();
        const bitmap_width = bitmap.width();

        freetype_font_interface.atlas_entries[codepoint_i] = try atlas.reserve(
            allocator,
            bitmap_width,
            bitmap_height,
        );

        const placement = freetype_font_interface.atlas_entries[codepoint_i];
        const texture_width = app_texture.dimensions.width;

        const bitmap_pixels = bitmap.buffer().?;

        var y: usize = 0;
        while (y < bitmap_height) : (y += 1) {
            var x: usize = 0;
            while (x < bitmap_width) : (x += 1) {
                const value = @intToFloat(f32, bitmap_pixels[x + (y * bitmap_width)]);
                app_texture.pixels[(placement.x + x) + ((y + placement.y) * texture_width)] = .{
                    .r = 0.8,
                    .g = 0.8,
                    .b = 0.8,
                    .a = value / 255,
                };
            }
        }
    }

    //
    // Setup Fontana
    //

    fontana_font_interface = .{
        .font = &font,
        .atlas = &atlas,
        .codepoints = atlas_codepoints,
        .atlas_entries = undefined,
        .font_scale = undefined,
    };

    const ppi = 100;
    const funit_to_pixel = otf.fUnitToPixelScale(point_size, ppi, font.units_per_em);
    for (atlas_codepoints) |codepoint, codepoint_i| {
        const required_dimensions = try otf.getRequiredDimensions(&font, codepoint, funit_to_pixel);
        fontana_font_interface.atlas_entries[codepoint_i] = try atlas.reserve(
            allocator,
            required_dimensions.width,
            required_dimensions.height,
        );
        var pixel_writer = fontana.rasterizer.SubTexturePixelWriter(PixelType){
            .texture_width = app_texture.dimensions.width,
            .pixels = @ptrCast([*]fontana.graphics.RGBA(f32), app_texture.pixels),
            .write_extent = fontana_font_interface.atlas_entries[codepoint_i],
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
    app.onResize = onResize;

    try app.doLoop();
}

fn onResize(width: f32, height: f32) void {
    std.log.info("Resizing: {d}, {d}", .{ width, height });
    const scale_factor = app.scaleFactor();
    fontana.drawText(
        render_text,
        .{ .x = -0.8, .y = 0.0 },
        .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
        point_size,
        &text_writer_interface,
        &fontana_font_interface,
    ) catch |err| {
        std.log.err("Failed to draw text. Error: {}", .{err});
    };

    fontana.drawText(
        render_text,
        .{ .x = -0.8, .y = 0.2 },
        .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
        point_size,
        &text_writer_interface,
        &freetype_font_interface,
    ) catch |err| {
        std.log.err("Failed to draw text. Error: {}", .{err});
    };
}
