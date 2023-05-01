const std = @import("std");
const libxml2 = @import("dep/zig-libxml2/libxml2.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_archive = b.dependency("zig_archive", .{});

    const archive_mod = zig_archive.module("archive");

    const xml = try libxml2.create(b, target, optimize, .{
        .iconv = false,
        .lzma = false,
        .zlib = false,
    });

    // TODO: figure out linking/includes for c dependencies with package manager
    const cyborg_module = b.addModule("cyborg", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{.{
            .name = "archive",
            .module = archive_mod,
        }},
    });
    _ = cyborg_module;

    const lib = b.addStaticLibrary(.{
        .name = "cyborg",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addModule("archive", archive_mod);
    xml.link(lib);

    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const exe = b.addExecutable(.{
        .name = "cyborg",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("archive", zig_archive.module("archive"));
    xml.link(exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
