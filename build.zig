// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");

const vkgen = @import("libs/vulkan-zig/generator/index.zig");

const Builder = std.build.Builder;
const Build = std.build;
const Pkg = Build.Pkg;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "fontana-examples",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
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

    glfwLink(b, exe);

    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run fontana-example");
    run_step.dependOn(&run_cmd.step);
}

// NOTE: This is a hack while the mach-glfw build system is stabalizing
fn glfwLink(b: *std.Build, step: *std.build.CompileStep) void {
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = step.target,
        .optimize = step.optimize,
    });
    step.linkLibrary(glfw_dep.artifact("mach-glfw"));
    step.addModule("glfw", glfw_dep.module("mach-glfw"));

    @import("glfw").addPaths(step);
    step.linkLibrary(b.dependency("vulkan_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("vulkan-headers"));
    step.linkLibrary(b.dependency("x11_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("x11-headers"));
    step.linkLibrary(b.dependency("wayland_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("wayland-headers"));
}
