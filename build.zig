const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zengine = b.dependency("zengine", .{});
    const zmod = zengine.module("zengine");
    const z = @import("zengine");
    const options = z.getOptions(b);

    const install_assets = try z.addInstallAssets(b);

    const core = b.createModule(.{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = core },
            .{ .name = "zengine", .module = zmod },
        },
        .pic = true,
    });

    const gen_menu_bg_mod = b.createModule(.{
        .root_source_file = b.path("src/gen_menu_bg.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = core },
            .{ .name = "zengine", .module = zmod },
        },
    });

    const check = b.addExecutable(.{
        .name = "cathode-run",
        .root_module = exe_mod,
    });

    const exe = b.addExecutable(.{
        .name = "cathode-run",
        .root_module = exe_mod,
    });
    exe.each_lib_rpath = false;
    const install_exe = b.addInstallArtifact(exe, .{});
    install_exe.step.dependOn(&install_assets.step);
    b.getInstallStep().dependOn(&install_exe.step);

    const gen_menu_bg_exe = b.addExecutable(.{
        .name = "gen-menu-bg",
        .root_module = gen_menu_bg_mod,
    });

    _ = try z.addExternal(b, .{
        .b = zengine.builder,
        .options = options,
        .target = target,
        .optimize = optimize,
    });

    const install_libs = try z.addInstallLibs(b, .{
        .b = zengine.builder,
        .module = zmod,
        .options = options,
        .target = target,
        .optimize = optimize,
    });
    exe.step.dependOn(install_libs);
    exe.each_lib_rpath = false;

    {
        const install_shaders_dir = try z.addCompileShaders(b, .{
            .b = zengine.builder,
            .module = zmod,
            .options = options,
            .optimize = optimize,
        });
        install_exe.step.dependOn(&install_shaders_dir.step);
    }
    const install_shaders = blk: {
        const install_shaders_dir = try z.addCompileShaders(b, .{
            .b = zengine.builder,
            .src = b.path("shaders"),
            .module = zmod,
            .options = options,
            .optimize = optimize,
        });
        install_exe.step.dependOn(&install_shaders_dir.step);
        break :blk install_shaders_dir;
    };

    _ = try z.addBundleMacOSApp(b, .{
        .app_dirname = "Cathode Run.app",
        .exe_app_filename = "CathodeRun",
        .install_exe = install_exe,
        .install_libs = install_libs,
        .install_resources = &.{
            install_assets,
            install_shaders,
        },
    });

    const check_step = b.step("check", "Check the app");
    check_step.dependOn(&check.step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_exe.step);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const gen_menu_bg_step = b.step("gen-menu-bg", "Generate menu background");
    const gen_menu_bg_cmd = b.addRunArtifact(gen_menu_bg_exe);
    gen_menu_bg_step.dependOn(&gen_menu_bg_cmd.step);

    if (b.args) |args| gen_menu_bg_cmd.addArgs(args);

    const mod_tests = b.addTest(.{
        .root_module = core,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
