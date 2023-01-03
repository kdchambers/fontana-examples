// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");

const glfw = @import("libs/mach-glfw/build.zig");
const vkgen = @import("libs/vulkan-zig/generator/index.zig");
const freetype = @import("libs/mach-freetype/build.zig");

const Builder = std.build.Builder;
const Build = std.build;
const Pkg = Build.Pkg;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("fontana-example", "src/main.zig");

    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addPackage(.{
        .name = "shaders",
        .source = .{ .path = "shaders/shaders.zig" },
    });

    exe.addPackage(.{
        .name = "fontana",
        .source = .{ .path = "libs/fontana/src/fontana.zig" },
    });

    const gen = vkgen.VkGenerateStep.create(b, "vk.xml", "vk.zig");
    const vulkan_pkg = gen.getPackage("vulkan");

    const glfw_pkg = glfw.pkg(b);
    const freetype_pkg = freetype.pkg(b);
    const harfbuzz_pkg = freetype.harfbuzz_pkg(b);

    exe.addPackage(vulkan_pkg);
    exe.addPackage(glfw_pkg);
    exe.addPackage(freetype_pkg);
    exe.addPackage(harfbuzz_pkg);

    freetype.link(b, exe, .{ .harfbuzz = .{ .install_libs = false } });
    try glfw.link(b, exe, .{});

    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    if (b.args) |args| run_cmd.addArgs(args);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run fontana-example");
    run_step.dependOn(&run_cmd.step);
}
