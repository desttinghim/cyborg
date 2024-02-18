const std = @import("std");

const Builder = std.Build;

const tests = .{
    "read_zip",
    "write_zip",
};

const bench = .{
    "bench_zip",
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const archive_module = b.addModule("archive", .{
        .root_source_file = .{ .path = "src/main.zig" },
    });

    // Library Tests

    const lib_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const lib_tests_step = b.step("test", "Run all library tests");
    lib_tests_step.dependOn(&lib_tests.step);

    // Test Runners

    inline for (tests) |file| {
        const zip_runner = b.addExecutable(.{
            .name = file,
            .root_source_file = .{ .path = "tests/" ++ file ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        zip_runner.linkLibC();

        zip_runner.root_module.addImport("archive", archive_module);

        _ = b.addInstallArtifact(zip_runner, .{});
        const run_zip_runner = b.addRunArtifact(zip_runner);

        const run_tests = b.step(file, "Run tests");
        run_tests.dependOn(&run_zip_runner.step);
    }

    // Benchmarks

    const preallocate = b.option(bool, "preallocate", "Allocate the file into memory rather than reading from disk [true].") orelse true;
    const void_write = b.option(bool, "void_write", "Write to a void file rather than a real file when extracting [true].") orelse true;
    const runtime = b.option(u32, "runtime", "How long to run benchmarks in seconds [60].") orelse 60;

    const bench_options = b.addOptions();
    bench_options.addOption(bool, "preallocate", preallocate);
    bench_options.addOption(bool, "void_write", void_write);
    bench_options.addOption(u32, "runtime", runtime);

    inline for (bench) |file| {
        const zip_bench = b.addExecutable(.{
            .name = file,
            .root_source_file = .{ .path = "tests/" ++ file ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        zip_bench.root_module.addOptions("build_options", bench_options);
        zip_bench.root_module.addImport("archive", archive_module);

        _ = b.addInstallArtifact(zip_bench, .{});
        const run_zip_bench = b.addRunArtifact(zip_bench);

        const zip_bench_step = b.step(file, "Run benchmark");
        zip_bench_step.dependOn(&run_zip_bench.step);
    }
}
