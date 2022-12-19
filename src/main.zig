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
const FontAdapter = Atlas.FontAdapter;

const fontana_font_adapter = struct {
    const CodepointType = Atlas.CodepointType;
    const PixelType = Atlas.PixelType;

    pub fn scaleForPixelHeight(self: *const FontAdapter, height_pixels: f32) f32 {
        const font = @ptrCast(*otf.FontInfo, self.internal);
        return otf.scaleForPixelHeight(font, height_pixels);
    }

    pub fn advanceHorizontalList(self: *const FontAdapter, codepoints: []const CodepointType, out_advance_list: []u16) void {
        const font = @ptrCast(*otf.FontInfo, self.internal);
        otf.loadXAdvances(font, codepoints, out_advance_list);
    }

    pub fn kernPairList(
        self: *const FontAdapter,
        allocator: std.mem.Allocator,
        codepoints: []const CodepointType,
    ) error{ InvalidFont, InvalidCodepoint, OutOfMemory }![]otf.KernPair {
        const font = @ptrCast(*const otf.FontInfo, self.internal);
        return otf.generateKernPairsFromGpos(allocator, font, codepoints) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidFont,
            };
        };
    }

    pub fn glyphBoundingBox(
        self: *const FontAdapter,
        codepoint: CodepointType,
    ) error{Unknown}!geometry.BoundingBox(i32) {
        const font = @ptrCast(*const otf.FontInfo, self.internal);
        return otf.boundingBoxForCodepoint(font, @intCast(i32, codepoint)) catch {
            return error.Unknown;
        };
    }

    pub fn rasterizeGlyph(
        self: *const FontAdapter,
        allocator: std.mem.Allocator,
        codepoint: CodepointType,
        scale: f32,
        texture_pixels: [*]PixelType,
        texture_dimensions: geometry.Dimensions2D(u32),
        extent: geometry.Extent2D(u32),
    ) error{ Unknown, OutOfMemory, InvalidInput }!void {
        const font = @ptrCast(*const otf.FontInfo, self.internal);
        var pixel_writer = fontana.rasterizer.SubTexturePixelWriter(PixelType){
            .texture_width = texture_dimensions.width,
            .write_extent = extent,
            .pixels = texture_pixels,
        };
        _ = otf.rasterizeGlyph(allocator, pixel_writer, font, scale, codepoint) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.Unknown,
            };
        };
    }
};

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

    const pixel_count = @intCast(usize, app_texture.dimensions.width) * app_texture.dimensions.height;
    std.mem.set(graphics.RGBA(f32), app_texture.pixels[0..pixel_count], .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 });

    const fontana_adapter = Atlas.FontAdapter{
        .internal = @ptrCast(*FontAdapter.Internal, &font),
        .scaleForPixelHeight = fontana_font_adapter.scaleForPixelHeight,
        .advanceHorizontalList = fontana_font_adapter.advanceHorizontalList,
        .kernPairList = fontana_font_adapter.kernPairList,
        .glyphBoundingBox = fontana_font_adapter.glyphBoundingBox,
        .rasterizeGlyph = fontana_font_adapter.rasterizeGlyph,
    };

    const codepoints = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
    try font_atlas.init(
        allocator,
        &fontana_adapter,
        codepoints,
        20,
        font.space_advance,
        @ptrCast([*]fontana.graphics.RGBA(f32), app_texture.pixels),
        .{
            .width = app_texture.dimensions.width,
            .height = app_texture.dimensions.height,
        },
    );
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
    font_atlas.drawText(&text_writer_interface, "Hello", .{ .x = 0.0, .y = 0.0 }, scale_factor) catch |err| {
        std.log.warn("Failed to draw text. Error: {}", .{err});
    };
}
