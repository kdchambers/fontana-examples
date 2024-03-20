// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keith Chambers

const std = @import("std");

const Build = std.Build;
const Pkg = Build.Pkg;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "fontana-examples",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const module_shaders = b.createModule(.{
        .root_source_file = .{ .path = "shaders/shaders.zig" },
    });

    exe.root_module.addImport("shaders", module_shaders);

    const vkzig_dep = b.dependency("vulkan_zig", .{
        .registry = @as([]const u8, b.pathFromRoot("vk.xml")),
    });
    const vkzig_bindings = vkzig_dep.module("vulkan-zig");
    exe.root_module.addImport("vulkan", vkzig_bindings);

    const glfw_dep = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("mach-glfw", glfw_dep.module("mach-glfw"));

    const fontana_dep = b.dependency("fontana", .{
        .target = target,
        .optimize = optimize,
    });
    const fontana_module = fontana_dep.module("fontana");
    exe.root_module.addImport("fontana", fontana_module);

    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run fontana-example");
    run_step.dependOn(&run_cmd.step);
}
