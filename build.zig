const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const install_assets = b.addInstallDirectory(.{
        .source_dir = b.path("assets"),
        .install_dir = .prefix,
        .install_subdir = "assets",
    });
    b.getInstallStep().dependOn(&install_assets.step);

    const core = b.createModule(.{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });

    const term_mod = b.createModule(.{
        .root_source_file = b.path("src/terminal.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = core },
        },
        .link_libc = true,
    });
    term_mod.addCSourceFile(.{ .file = b.path("vendor/miniaudio/miniaudio.c") });
    term_mod.addIncludePath(b.path("vendor/miniaudio"));

    if (target.result.os.tag == .macos) {
        term_mod.linkFramework("CoreAudio", .{ .needed = true });
        term_mod.linkFramework("CoreFoundation", .{});
        term_mod.linkFramework("AudioUnit", .{});
        term_mod.linkFramework("AudioToolbox", .{});
    }

    const check_term = b.addExecutable(.{
        .name = "cathode-run",
        .root_module = term_mod,
    });

    const term_exe = b.addExecutable(.{
        .name = "cathode-run",
        .root_module = term_mod,
    });

    b.installArtifact(term_exe);

    const check_step = b.step("check", "Check the app");
    check_step.dependOn(&check_term.step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(term_exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = core,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
