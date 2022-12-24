const std = @import("std");
const libxml2 = @import("dep/zig-libxml2/libxml2.zig");

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    const zig_archive = std.build.Pkg{
        .name = "archive",
        .source = .{ .path = "dep/zig-archive/src/main.zig" },
    };

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const xml = try libxml2.create(b, target, mode, .{
        .iconv = false,
        .lzma = false,
        .zlib = false,
    });

    const lib = b.addStaticLibrary("zandroid", "src/main.zig");
    lib.addPackage(zig_archive);
    lib.setBuildMode(mode);
    xml.link(lib);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const exe = b.addExecutable("zandroid", "src/main.zig");
    exe.addPackage(zig_archive);
    exe.setBuildMode(mode);
    exe.setTarget(target);
    xml.link(exe);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
