const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_archive = b.dependency("zig_archive", .{});

    const archive_mod = zig_archive.module("archive");

    const cyborg_module = b.addModule("cyborg", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{.{
            .name = "archive",
            .module = archive_mod,
        }},
    });
    _ = cyborg_module;

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addModule("archive", archive_mod);

    const run_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    const exe = b.addExecutable(.{
        .name = "cyborg",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("archive", zig_archive.module("archive"));

    b.installArtifact(exe);

    const dexter_exe = b.addExecutable(.{
        .name = "dexter",
        .root_source_file = .{ .path = "src/dexter.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(dexter_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_dexter_cmd = b.addRunArtifact(dexter_exe);
    run_dexter_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_dexter_cmd.addArgs(args);
    }

    const run_dexter_step = b.step("run-dexter", "Run the app");
    run_dexter_step.dependOn(&run_dexter_cmd.step);
}

// TODO:
// pub fn addApk() { }

// pub const ApkStep = struct {
//     files: std.ArrayList(std.Build.FileSource),
//
//
//     const ApkFile = struct {
//         compress: bool,
//         align: ?enum { align4k } = null,
//     };
// };

pub const ApplicationOptions = struct {
    api_level: []const u8,
};

pub fn addApplication() AndroidApplication {}

/// Represents an Android Application, which is a collection of components
/// that all represent different entry points
pub const AndroidApplication = struct {
    components: std.ArrayListUnmanaged(),

    pub const Component = union(enum) {
        activity: Activity,
        service: Service,
        broadcast_receiver: BroadcastReceiver,
        content_provider: ContentProvider,
    };

    /// Application entry point for providing a graphical user interface
    pub const Activity = struct {
        kind: ActivityKind,

        pub const ActivityKind = union(enum) {
            dex: std.Build.FileSource,
            native: std.Build.FileSource,
        };
    };
    /// Application entry point for long-running operations
    pub const Service = struct {
        dex: std.Build.FileSource,
    };
    /// Application entry point for responding to system events
    pub const BroadcastReceiver = struct {
        dex: std.Build.FileSource,
    };
    /// Application entry point for mapping data to URIs
    pub const ContentProvider = struct {
        dex: std.Build.FileSource,
    };
    /// Files depended on by the application - includes application icons
    pub const Resource = struct {
        pub const ResourceKind = union(enum) {
            drawable: std.Build.FileSource,
        };
    };
};
