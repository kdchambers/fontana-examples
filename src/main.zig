// SPDX-License-Identifier: MIT
// Copyright (c) 2023 Keith Chambers

const std = @import("std");
const fontana = @import("fontana");
const app = @import("app.zig");

const graphics = @import("graphics.zig");
const GenericVertex = graphics.GenericVertex;

const geometry = @import("geometry.zig");
const Extent2D = geometry.Extent2D;

const builtin = @import("builtin");
const build_mode = builtin.mode;
const is_debug = (build_mode == .Debug);

const TextWriterInterface = struct {
    quad_writer: *app.QuadFaceWriter(GenericVertex),
    pub fn write(
        self: *@This(),
        screen_extent: geometry.Extent2D(f32),
        texture_extent: geometry.Extent2D(f32),
    ) !void {
        (try self.quad_writer.create()).* = graphics.generateTexturedQuad(
            GenericVertex,
            screen_extent,
            texture_extent,
            .bottom_left,
        );
    }
};

const application_name = "fontana tester";

const fonts = struct {
    const dejavu_sans = "assets/DejaVuSans.ttf";
    const roboto_light = "assets/Roboto-Light.ttf";
    const roboto_medium = "assets/Roboto-Medium.ttf";
    const roboto_mono = "assets/RobotoMono.ttf";
};

const atlas_codepoints = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!._,:";
const point_size_large: f64 = 16.0;
const point_size_small: f64 = 11.0;

//
// Color code the container rectangles
//
const color_fontana_small = graphics.RGBA(f32).fromInt(u8, 35, 65, 45, 255);
const color_fontana_large = graphics.RGBA(f32).fromInt(u8, 45, 75, 55, 255);
const color_freetype_small = graphics.RGBA(f32).fromInt(u8, 75, 45, 55, 255);
const color_freetype_large = graphics.RGBA(f32).fromInt(u8, 85, 55, 65, 255);
const color_harfbuzz_small = graphics.RGBA(f32).fromInt(u8, 50, 51, 31, 255);
const color_harfbuzz_large = graphics.RGBA(f32).fromInt(u8, 60, 61, 41, 255);

//
// This may be wrong and lead to incorrect results, depending on your physical output display
//
const points_per_pixel = 100;

const Atlas = fontana.Atlas;

var text_writer_interface: TextWriterInterface = undefined;

var gpa = if (is_debug) std.heap.GeneralPurposeAllocator(.{}){} else {};

var texture_dimensions: geometry.Dimensions2D(u16) = undefined;

//
// This allows us to inject our own types and avoid casting / re-creating
//
const standard_type_overrides = fontana.OverridableTypes{
    .Extent2DPixel = geometry.Extent2D(u32),
    .Extent2DNative = geometry.Extent2D(f32),
    .Coordinates2DNative = geometry.Coordinates2D(f32),
    .Scale2D = geometry.Scale2D(f64),
};

//
// We need to specify the pixel format of the bitmap texture where the glyphs
// will be rendered to. Defining PixelType is optional as each pixel_format
// has a default PixelType that can be used.
//
const standard_pen_options = fontana.PenOptions{
    .pixel_format = .r32g32b32a32,
    .PixelType = graphics.RGBA(f32),
};

//
// A Font type is generated for all three possible backends
//

const FontFontana = fontana.Font(.{
    .backend = .fontana,
    .type_overrides = standard_type_overrides,
});

const FontFreetype = fontana.Font(.{
    .backend = .freetype,
    .type_overrides = standard_type_overrides,
});

const FontFreetypeHarfbuzz = fontana.Font(.{
    .backend = .freetype_harfbuzz,
    .type_overrides = standard_type_overrides,
});

//
// For each font backend, we'll create two separate pens; One at a larger and smaller size
//

var pen_fontana_small: FontFontana.PenConfig(standard_pen_options) = undefined;
var pen_fontana_large: FontFontana.PenConfig(standard_pen_options) = undefined;

var pen_freetype_small: ?FontFreetype.PenConfig(standard_pen_options) = null;
var pen_freetype_large: ?FontFreetype.PenConfig(standard_pen_options) = null;

var pen_harfbuzz_small: ?FontFreetypeHarfbuzz.PenConfig(standard_pen_options) = null;
var pen_harfbuzz_large: ?FontFreetypeHarfbuzz.PenConfig(standard_pen_options) = null;

pub fn main() !void {
    var allocator = if (is_debug) gpa.allocator() else std.heap.c_allocator;
    defer {
        if (comptime is_debug) {
            _ = gpa.deinit();
        }
    }

    try app.init(allocator, application_name);
    const texture = app.getTextureMut();

    var fontana_font: FontFontana = blk: {
        const file_handle = try std.fs.cwd().openFile(fonts.dejavu_sans, .{ .mode = .read_only });
        defer file_handle.close();
        const max_size_bytes = 10 * 1024 * 1024; // 10mib
        const font_file_bytes = try file_handle.readToEndAlloc(allocator, max_size_bytes);
        break :blk FontFontana.construct(font_file_bytes);
    } catch |err| {
        std.log.err("Failed to load font file ({s}). Error: {}", .{ fonts.dejavu_sans, err });
        return err;
    };
    defer fontana_font.deinit(allocator);

    //
    // Freetype and Harfbuzz backends can fail if libraries aren't installed. In that case an error is
    // logged and only text from the fontana backend will be displayed
    //

    var freetype_font_opt: ?FontFreetype = blk: {
        const file_handle = try std.fs.cwd().openFile(fonts.roboto_mono, .{ .mode = .read_only });
        defer file_handle.close();
        const max_size_bytes = 10 * 1024 * 1024; // 10mib
        const font_file_bytes = try file_handle.readToEndAlloc(allocator, max_size_bytes);
        break :blk FontFreetype.construct(font_file_bytes) catch {
            std.log.warn("Failed to load freetype backend. Library may not be installed on system", .{});
            break :blk null;
        };
    };
    defer {
        if (freetype_font_opt) |*freetype_font| {
            freetype_font.deinit(allocator);
        }
    }

    var harfbuzz_font_opt: ?FontFreetypeHarfbuzz = blk: {
        const file_handle = try std.fs.cwd().openFile(fonts.roboto_medium, .{ .mode = .read_only });
        defer file_handle.close();
        const max_size_bytes = 10 * 1024 * 1024; // 10mib
        const font_file_bytes = try file_handle.readToEndAlloc(allocator, max_size_bytes);
        break :blk FontFreetypeHarfbuzz.construct(font_file_bytes) catch {
            std.log.warn("Failed to load freetype_harfbuzz backend. Freetype and/or Harfubzz libraries may not be installed on system", .{});
            break :blk null;
        };
    };
    defer {
        if (harfbuzz_font_opt) |*harfbuzz_font| {
            harfbuzz_font.deinit(allocator);
        }
    }

    texture_dimensions = .{
        .width = texture.dimensions.width,
        .height = texture.dimensions.height,
    };

    const font_setup_start = std.time.nanoTimestamp();

    var atlas = try Atlas.init(allocator, texture.dimensions.width);
    defer atlas.deinit(allocator);

    pen_fontana_small = try fontana_font.createPen(
        standard_pen_options,
        allocator,
        point_size_small,
        points_per_pixel,
        atlas_codepoints,
        texture.dimensions.width,
        @ptrCast([*]graphics.RGBA(f32), texture.pixels),
        &atlas,
    );
    pen_fontana_large = try fontana_font.createPen(
        standard_pen_options,
        allocator,
        point_size_large,
        points_per_pixel,
        atlas_codepoints,
        texture.dimensions.width,
        @ptrCast([*]graphics.RGBA(f32), texture.pixels),
        &atlas,
    );
    defer pen_fontana_small.deinit(allocator);
    defer pen_fontana_large.deinit(allocator);

    if (freetype_font_opt) |*freetype_font| {
        pen_freetype_small = try freetype_font.createPen(
            standard_pen_options,
            allocator,
            point_size_small,
            points_per_pixel,
            atlas_codepoints,
            texture.dimensions.width,
            @ptrCast([*]graphics.RGBA(f32), texture.pixels),
            &atlas,
        );
        pen_freetype_large = try freetype_font.createPen(
            standard_pen_options,
            allocator,
            point_size_large,
            points_per_pixel,
            atlas_codepoints,
            texture.dimensions.width,
            @ptrCast([*]graphics.RGBA(f32), texture.pixels),
            &atlas,
        );
    }
    defer {
        if (pen_freetype_small) |*pen|
            pen.deinit(allocator);
        if (pen_freetype_large) |*pen|
            pen.deinit(allocator);
    }

    if (harfbuzz_font_opt) |*harfbuzz_font| {
        pen_harfbuzz_small = try harfbuzz_font.createPen(
            standard_pen_options,
            allocator,
            point_size_small,
            points_per_pixel,
            atlas_codepoints,
            texture.dimensions.width,
            @ptrCast([*]graphics.RGBA(f32), texture.pixels),
            &atlas,
        );
        pen_harfbuzz_large = try harfbuzz_font.createPen(
            standard_pen_options,
            allocator,
            point_size_large,
            points_per_pixel,
            atlas_codepoints,
            texture.dimensions.width,
            @ptrCast([*]graphics.RGBA(f32), texture.pixels),
            &atlas,
        );
    }
    defer {
        if (pen_harfbuzz_small) |*pen|
            pen.deinit(allocator);
        if (pen_harfbuzz_large) |*pen|
            pen.deinit(allocator);
    }

    const font_setup_end = std.time.nanoTimestamp();
    const font_setup_duration = @intCast(u64, font_setup_end - font_setup_start);
    std.log.info("Font setup in {} in mode `{s}`", .{
        std.fmt.fmtDuration(font_setup_duration),
        @tagName(build_mode),
    });

    text_writer_interface = .{ .quad_writer = app.faceWriter() };
    app.onResize = onResize;

    try app.doLoop();
}

fn onResize(width: f32, height: f32) void {
    std.log.info("Resizing: {d}, {d}", .{ width, height });
    const scale_factor = app.scaleFactor();

    const large_container_dimensions = geometry.Dimensions2D(f32){
        .width = @floatCast(f32, 800 * scale_factor.horizontal),
        .height = @floatCast(f32, 80 * scale_factor.vertical),
    };
    const small_container_dimensions = geometry.Dimensions2D(f32){
        .width = @floatCast(f32, 600 * scale_factor.horizontal),
        .height = @floatCast(f32, 60 * scale_factor.vertical),
    };

    const placement_x_small: f32 = -1.0 + ((2.0 - small_container_dimensions.width) / 2.0);
    const placement_x_large: f32 = -1.0 + ((2.0 - large_container_dimensions.width) / 2.0);
    var placement_y: f32 = -0.5;

    var quad_writer = app.faceWriter();
    var quads = quad_writer.allocate(6) catch |err| {
        std.log.err("Failed to allocate quad. Error: {}", .{err});
        return;
    };

    const y_offset = @floatCast(f32, 100 * scale_factor.vertical);

    {
        const container_extent_small = geometry.Extent2D(f32){
            .x = placement_x_small,
            .y = placement_y,
            .width = small_container_dimensions.width,
            .height = small_container_dimensions.height,
        };
        const container_extent_large = geometry.Extent2D(f32){
            .x = placement_x_large,
            .y = placement_y + y_offset,
            .width = large_container_dimensions.width,
            .height = large_container_dimensions.height,
        };
        quads[0] = graphics.generateQuadColored(
            GenericVertex,
            .{
                .x = placement_x_small,
                .y = placement_y,
                .width = small_container_dimensions.width,
                .height = small_container_dimensions.height,
            },
            color_fontana_small,
            .bottom_left,
        );
        quads[1] = graphics.generateQuadColored(
            GenericVertex,
            .{
                .x = placement_x_large,
                .y = placement_y + y_offset,
                .width = large_container_dimensions.width,
                .height = large_container_dimensions.height,
            },
            color_fontana_large,
            .bottom_left,
        );

        pen_fontana_small.writeCentered(
            "Fontana: The quick brown fox jumps over the lazy dog.",
            container_extent_small,
            .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
            &text_writer_interface,
        ) catch |err| {
            std.log.err("Failed to draw text. Error: {}", .{err});
        };

        pen_fontana_large.writeCentered(
            "Fontana: The quick brown fox jumps over the lazy dog.",
            container_extent_large,
            .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
            &text_writer_interface,
        ) catch |err| {
            std.log.err("Failed to draw text. Error: {}", .{err});
        };
        placement_y += y_offset * 2;
    }

    var quad_index: u32 = 2;

    if (pen_freetype_small) |*pen| {
        const container = geometry.Extent2D(f32){
            .x = placement_x_small,
            .y = placement_y,
            .width = small_container_dimensions.width,
            .height = small_container_dimensions.height,
        };
        quads[quad_index] = graphics.generateQuadColored(
            GenericVertex,
            container,
            color_freetype_small,
            .bottom_left,
        );
        pen.writeCentered(
            "Freetype: The quick brown fox jumps over the lazy dog.",
            container,
            .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
            &text_writer_interface,
        ) catch |err| {
            std.log.err("Failed to draw text. Error: {}", .{err});
        };
        quad_index += 1;
        placement_y += y_offset;
    }

    if (pen_freetype_large) |*pen| {
        const container = geometry.Extent2D(f32){
            .x = placement_x_large,
            .y = placement_y,
            .width = large_container_dimensions.width,
            .height = large_container_dimensions.height,
        };
        quads[quad_index] = graphics.generateQuadColored(
            GenericVertex,
            container,
            color_freetype_large,
            .bottom_left,
        );
        pen.writeCentered(
            "Freetype: The quick brown fox jumps over the lazy dog.",
            container,
            .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
            &text_writer_interface,
        ) catch |err| {
            std.log.err("Failed to draw text. Error: {}", .{err});
        };
        quad_index += 1;
        placement_y += y_offset;
    }

    if (pen_harfbuzz_small) |*pen| {
        const container = geometry.Extent2D(f32){
            .x = placement_x_small,
            .y = placement_y,
            .width = small_container_dimensions.width,
            .height = small_container_dimensions.height,
        };
        quads[quad_index] = graphics.generateQuadColored(
            GenericVertex,
            container,
            color_harfbuzz_small,
            .bottom_left,
        );
        pen.writeCentered(
            "Harfbuzz: The quick brown fox jumps over the lazy dog.",
            container,
            .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
            &text_writer_interface,
        ) catch |err| {
            std.log.err("Failed to draw text. Error: {}", .{err});
        };
        quad_index += 1;
        placement_y += y_offset;
    }

    if (pen_harfbuzz_large) |*pen| {
        const container = geometry.Extent2D(f32){
            .x = placement_x_large,
            .y = placement_y,
            .width = large_container_dimensions.width,
            .height = large_container_dimensions.height,
        };
        quads[quad_index] = graphics.generateQuadColored(
            GenericVertex,
            container,
            color_harfbuzz_large,
            .bottom_left,
        );
        pen.writeCentered(
            "Harfbuzz: The quick brown fox jumps over the lazy dog.",
            container,
            .{ .horizontal = scale_factor.horizontal, .vertical = scale_factor.vertical },
            &text_writer_interface,
        ) catch |err| {
            std.log.err("Failed to draw text. Error: {}", .{err});
        };
        quad_index += 1;
        placement_y += y_offset;
    }
}
