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
        .source = .{ .path = "libs/fontana/fontana.zig" },
    });

    const gen = vkgen.VkGenerateStep.init(b, "vk.xml", "vk.zig");
    exe.addPackage(gen.package);

    exe.addPackage(glfw.pkg);
    try glfw.link(b, exe, .{});

    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    if (b.args) |args| run_cmd.addArgs(args);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run fontana-example");
    run_step.dependOn(&run_cmd.step);
}
