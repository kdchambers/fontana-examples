// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");

const glfw = @import("libs/mach-glfw/build.zig");
const vkgen = @import("libs/vulkan-zig/generator/index.zig");

const Builder = std.build.Builder;
const Build = std.build;
const Pkg = Build.Pkg;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize_mode = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "fontana-examples",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize_mode,
    });

    const module_shaders = b.createModule(.{
        .source_file = .{ .path = "shaders/shaders.zig" },
        .dependencies = &.{},
    });

    const module_fontana = b.createModule(.{
        .source_file = .{ .path = "libs/fontana/src/fontana.zig" },
        .dependencies = &.{},
    });
    exe.addModule("shaders", module_shaders);
    exe.addModule("fontana", module_fontana);

    const gen = vkgen.VkGenerateStep.create(b, "vk.xml");
    exe.addModule("vulkan", gen.getModule());

    const glfw_module = glfw.module(b);
    exe.addModule("glfw", glfw_module);

    try glfw.link(b, exe, .{});

    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    if (b.args) |args| run_cmd.addArgs(args);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run fontana-example");
    run_step.dependOn(&run_cmd.step);
}
