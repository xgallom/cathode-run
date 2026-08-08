const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.main);
const Allocator = std.mem.Allocator;

const zengine = @import("zengine");
const Zengine = zengine.Zengine;
const allocators = zengine.allocators;
const ecs = zengine.ecs;
const Event = zengine.Event;
const gfx = zengine.gfx;
const Scene = zengine.gfx.Scene;
const global = zengine.global;
const math = zengine.math;
const perf = zengine.perf;
const c = zengine.ext.c;
const scheduler = zengine.scheduler;
const time = zengine.time;
const Engine = zengine.Engine;
const ui = zengine.ui;
const str = zengine.str;

const Assets = @import("Assets.zig");
const vfx_pass = @import("vfx_pass.zig");
const core = @import("core");
const static = core.static;
const game_render = @import("render.zig");

pub const cathode_run_options = core.cathode_run_options;

pub const zengine_options: zengine.Options = .{
    .has_debug_ui = false,
    .log_allocations = false,
};

pub const std_options: std.Options = .{
    .log_level = .info,
    .log_scope_levels = core.std_options.log_scope_levels,
    .logFn = logFn,
};

const RenderPasses = struct {
    render: gfx.pass.Render = .{
        .exposure = 1,
        .gamma = 1,
        .config = .{
            .has_agx = false,
            .has_lut = false,
            .has_srgb = true,
        },
    },
};

const lut_key = "lut/basic.cube";
const font_key = "fonts/Ac437_IBM_VGA_9x16.ttf";

var gfx_loader: gfx.Loader = undefined;
var gfx_passes: RenderPasses = .{};
var gfx_fence: gfx.GPUFence = .invalid;

var allocs_window: zengine.ui.AllocsWindow = undefined;
var perf_window: zengine.ui.PerfWindow = undefined;
var log_window: zengine.ui.LogWindow = .invalid;

var stderr_buf: [1 << 16]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
const stderr = &stderr_writer.interface;

var state: State = undefined;

const RunCounter = time.Counter;

const State = struct {
    assets: Assets,
    game: core.state.GameState,
    frame: core.state.Frame,
    run_counter: RunCounter = .init(1),
    rnd: std.Random.DefaultPrng,
    active_music: ?[]const u8 = null,
    input_idx: usize = 0,

    fn init(win_size: core.game.Point.U) !@This() {
        return .{
            .assets = try .init(allocators.global()),
            .game = try .init(allocators.gpa(), win_size),
            .frame = try .init(allocators.gpa(), win_size),
            .rnd = .init(0),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.game.deinit(allocators.gpa());
        self.frame.deinit(allocators.gpa());
    }

    pub fn tick(self: *@This()) !bool {
        self.run_counter.add(1);
        while (self.run_counter.run()) {
            const to = try core.update(&self.game);
            state.game.input_buf[0] = .none;
            state.input_idx = 0;

            try core.render(&self.game, &self.frame);
            self.run_counter.interval = core.sleep(&self.game);
            switch (try core.transfer(&self.game, to)) {
                .init => {
                    if (cathode_run_options.random_seed orelse !cathode_run_options.debug) {
                        self.game.session.seed = try self.rnd.next();
                    } else {
                        self.game.session.seed = 0;
                    }
                    log.info("reset seed: {x:016}", .{self.game.session.seed});
                },
                .end => return false,
                else => {},
            }
        }
        return true;
    }
};

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    log_window.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch |err| {
        std.log.defaultLog(.err, .default, "failed printing to log window: {t}", .{err});
    };
    std.log.defaultLog(message_level, scope, format, args);
}

pub fn main() !void {
    allocators.init(1_000_000_000);
    defer allocators.deinit();

    log_window = try .init(allocators.gpa());
    defer log_window.deinit();

    // log_window = try .init(allocators.gpa());
    // defer log_window.deinit();

    var engine = try Zengine.create(.{
        // .register = &register,
        .load = &load,
        .unload = &unload,
        .input = &input,
        .update = &update,
        .render = &render,
    }, &.{
        .title = "Cathode Run",
        // .size = .{ 1920, 1080 },
        .flags = .initMany(&.{ .high_pixel_density, .resizable, .fullscreen }),
    });
    defer engine.deinit();

    const args = global.args();
    if (args.len > 1) return error.TooManyArguments;

    return engine.run();
}

fn load(self: *const Zengine) !bool {
    gfx_loader = try .init(self.renderer);
    errdefer gfx_loader.deinit();
    {
        errdefer gfx_loader.cancel();
        try gfx_loader.createGraphicsPipelines();
        try game_render.createGamePipeline(&gfx_loader);
        try vfx_pass.init(&gfx_loader);

        try gfx.pass.Bloom.init(&gfx_loader);

        const main_win = self.engine.windows.getPtr("main");
        _ = try gfx_loader.loadLut(lut_key);
        const font = try gfx_loader.loadFont(font_key, 32);
        _ = try gfx_loader.createSurfaceTexture("messages_buffer", main_win.logicalSize(), .default);

        const frame_buffer = try gfx_loader.renderer.getOrCreateStorageBuffer("frame_buffer");
        {
            const gpa = gfx_loader.renderer.allocator;
            for (0..game_render.cells[1]) |_| {
                for (0..game_render.cells[0]) |_| {
                    try frame_buffer.append(
                        gpa,
                        .vertex,
                        [2]math.Vector4,
                        0,
                        &.{ math.vector4.zero, math.vector4.zero },
                    );
                }
            }
            try gfx_loader.flagModified(.storage_buffer, "frame_buffer");
        }

        const surf_size = game_render.surf_size;
        const surf_tex = try gfx_loader.createSurfaceTexture("game_screen", surf_size, .default);
        {
            const surf = surf_tex.surf;
            const scr = surf.slice(u32);
            assert(surf.width() * surf.height() == surf_size[0] * surf_size[1]);
            for (0..surf_size[1]) |y| {
                for (0..surf_size[0]) |x| {
                    const w = surf_size[0] - 1;
                    const h = surf_size[1] - 1;
                    const is_g = x == 0 and y == 0 or x == w and y == 0 or
                        x == 0 and y == h or x == w and y == h;
                    scr[y * surf_size[0] + x] = surf.rgba(.{
                        @intCast(255 * x / surf_size[0]),
                        if (is_g) 255 else 0,
                        @intCast(128 * y / surf_size[1]),
                        1,
                    });
                }
            }
        }

        const font_atlas = try gfx_loader.createSurfaceTexture(
            "font_atlas",
            game_render.font_atlas_size,
            .default,
        );
        for (0..256) |ch| {
            const codepoint = core.cp437.resolveUnicode(@intCast(ch));
            var surf = try font.renderGlyph(codepoint, .{ 255, 255, 255, 255 });
            defer surf.deinit();
            const x: i32 = @intCast(ch % 16);
            const y: i32 = @intCast(ch / 16);
            try font_atlas.surf.blitScaled(&.{
                x * @as(i32, @intCast(game_render.ch_size[0])),
                y * @as(i32, @intCast(game_render.ch_size[1])),
                @as(i32, @intCast(game_render.ch_size[0])),
                @as(i32, @intCast(game_render.ch_size[1])),
            }, surf, &.{ 0, 0, @intCast(surf.width()), @intCast(surf.height()) }, .pixelart);
        }
        gfx_fence = try gfx_loader.commit();
    }

    Zengine.sections.sub(.load).sub(.ui).begin();

    allocs_window = .init();
    perf_window = .init(allocators.global());

    Zengine.sections.sub(.load).sub(.ui).end();
    allocators.scratchRelease();

    state = try .init(.{ .x = game_render.cells[0], .y = game_render.cells[1] });
    try readSettings(&state.game.ui.settings);
    try loadSound(self, try state.assets.assetPath(.samples, static.asset.sample.activate), .oneshot);
    try loadSound(self, try state.assets.assetPath(.samples, static.asset.sample.explosion), .oneshot);
    try loadSound(self, try state.assets.assetPath(.samples, static.asset.sample.woosh), .oneshot);
    try loadSound(self, try state.assets.assetPath(.samples, static.asset.sample.engine_idle), .movement);
    try loadSound(self, try state.assets.assetPath(.samples, static.asset.sample.engine_x), .movement);
    try loadSound(self, try state.assets.assetPath(.samples, static.asset.sample.engine_y), .movement);

    for (&static.asset.music.levels) |level| try loadSound(
        self,
        try state.assets.assetPath(.music, level),
        .music,
    );
    try loadSound(self, try state.assets.assetPath(.music, static.asset.music.menu), .music);

    try reset();
    // try Message.add("Press space to start...");
    try self.engine.setCursorVisible(false);

    return true;
}

fn loadSound(
    self: *const Zengine,
    path: [:0]const u8,
    config: enum { oneshot, movement, music },
) !void {
    var audio = try zengine.audio.loader.loadFile(&.{
        .allocator = allocators.gpa(),
        .mixer = self.audio.mixer,
        .file_path = path,
    });
    errdefer audio.deinit();
    var track = try zengine.audio.Track.init(self.audio.mixer);
    errdefer track.deinit();
    assert(audio.isValid());
    assert(track.isValid());
    switch (config) {
        .oneshot => {
            const gain: f32 = @as(f32, @floatFromInt(state.game.ui.settings[2])) / 10.0;
            try track.setGain(gain);
        },
        .movement => {
            const gain: f32 = @as(f32, @floatFromInt(state.game.ui.settings[3])) / 10.0;
            try track.setGain(gain);
            try track.setLooping(true);
            try track.setFadeIn(cathode_run_options.movement_fade_in_ms);
            try track.setFadeOut(cathode_run_options.movement_fade_out_ms);
        },
        .music => {
            const gain: f32 = @as(f32, @floatFromInt(state.game.ui.settings[4])) / 10.0;
            try track.setGain(gain);
            try track.setLooping(true);
            try track.setFadeIn(cathode_run_options.music_fade_in_ms);
            try track.setFadeOut(cathode_run_options.music_fade_in_ms);
        },
    }
    try track.setAudio(audio);
    try self.audio.audios.insert(self.audio.allocator, path, audio);
    try self.audio.tracks.insert(self.audio.allocator, path, track);
}

fn reset() !void {}

fn unload(self: *const Zengine) !void {
    state.deinit();
    allocs_window.deinit();
    perf_window.deinit();
    gfx_loader.deinit();
    if (gfx_fence.isValid()) {
        self.renderer.gpu_device.wait(.any, &.{gfx_fence}) catch unreachable;
        self.renderer.gpu_device.release(&gfx_fence);
    }
    try stderr.flush();
}

fn input(self: *const Zengine) !bool {
    while (Event.poll()) |event| {
        if (self.ui.show_ui and c.ImGui_ImplSDL3_ProcessEvent(&event.sdl)) {
            switch (event.type) {
                .quit => return false,
                .key_down => {
                    if (event.sdl.key.repeat) break;
                    switch (event.sdl.key.key) {
                        c.SDLK_F1 => self.ui.show_ui = !self.ui.show_ui,
                        c.SDLK_ESCAPE => self.ui.show_ui = !self.ui.show_ui,
                        else => {},
                    }
                },
                else => {},
            }
            continue;
        }

        switch (event.type) {
            .quit => return false,
            .key_down => {
                if (event.sdl.key.repeat) break;
                switch (event.sdl.key.key) {
                    c.SDLK_F1 => self.ui.show_ui = !self.ui.show_ui,
                    c.SDLK_F10 => try reset(),
                    c.SDLK_ESCAPE => return false,
                    else => {
                        assert(state.input_idx < state.game.input_buf.len);
                        state.game.input_buf[state.input_idx] = .down(@intCast(event.sdl.key.key));
                        state.input_idx += 1;
                    },
                }
            },
            .key_up => switch (event.sdl.key.key) {
                else => {
                    assert(state.input_idx < state.game.input_buf.len);
                    state.game.input_buf[state.input_idx] = .up(@intCast(event.sdl.key.key));
                    state.input_idx += 1;
                },
            },
            else => {},
        }
    }
    state.game.input_buf[state.input_idx] = .none;
    return true;
}

fn update(self: *const Zengine) !bool {
    if (!try state.tick()) return false;
    if (state.game.session.state == .settings) {
        try updateSettings(&state.game.ui.settings);
        {
            const gain: f32 = @as(f32, @floatFromInt(state.game.ui.settings[2])) / 10.0;
            try updateGain(self.audio.tracks.get(
                try state.assets.assetPath(.samples, static.asset.sample.activate),
            ), gain);
            try updateGain(self.audio.tracks.get(
                try state.assets.assetPath(.samples, static.asset.sample.explosion),
            ), gain);
            try updateGain(self.audio.tracks.get(
                try state.assets.assetPath(.samples, static.asset.sample.woosh),
            ), gain);
        }
        {
            const gain: f32 = @as(f32, @floatFromInt(state.game.ui.settings[3])) / 10.0;
            try updateGain(self.audio.tracks.get(
                try state.assets.assetPath(.samples, static.asset.sample.engine_idle),
            ), gain);
            try updateGain(self.audio.tracks.get(
                try state.assets.assetPath(.samples, static.asset.sample.engine_x),
            ), gain);
            try updateGain(self.audio.tracks.get(
                try state.assets.assetPath(.samples, static.asset.sample.engine_y),
            ), gain);
        }
        {
            const gain: f32 = @as(f32, @floatFromInt(state.game.ui.settings[4])) / 10.0;
            for (static.asset.music.levels) |path| {
                try updateGain(self.audio.tracks.get(
                    try state.assets.assetPath(.music, path),
                ), gain);
            }
            try updateGain(self.audio.tracks.get(
                try state.assets.assetPath(.music, static.asset.music.menu),
            ), gain);
        }
    }
    while (state.game.sample_queue.pop()) |cmd| {
        switch (cmd) {
            .start => |path| try self.audio.tracks.get(
                try state.assets.assetPath(.samples, path),
            ).play(),
            .stop => |path| try self.audio.tracks.get(
                try state.assets.assetPath(.samples, path),
            ).stop(),
        }
    }
    while (state.game.music_queue.pop()) |new_path| {
        if (state.active_music) |path| {
            try self.audio.tracks.get(path).stop();
        }
        if (new_path) |path| {
            state.active_music = try state.assets.assetPath(.music, path);
            try self.audio.tracks.get(state.active_music.?).play();
        }
    }
    {
        errdefer gfx_loader.cancel();
        const gpa = gfx_loader.renderer.allocator;

        const frame_buffer = try gfx_loader.renderer.getOrCreateStorageBuffer("frame_buffer");
        frame_buffer.clearCPUBuffers();
        const frame = state.frame;
        for (0..game_render.cells[1]) |y| {
            for (0..game_render.cells[0]) |x| {
                const offset = y * game_render.cells[0] + x;
                const attrs = frame.attrs[offset];
                const bg = static.clr.rgb_f32[attrs.bg];
                const fg = static.clr.rgb_f32[attrs.fg];
                try frame_buffer.append(gpa, .vertex, [2]math.Vector4, 0, &.{
                    .{ bg[0], bg[1], bg[2], @floatFromInt(frame.syms[offset]) },
                    .{ fg[0], fg[1], fg[2], 0 },
                });
            }
        }
        try gfx_loader.flagModified(.storage_buffer, "frame_buffer");

        if (gfx_fence.isValid()) {
            try self.renderer.gpu_device.wait(.any, &.{gfx_fence});
            self.renderer.gpu_device.release(&gfx_fence);
        }
        gfx_fence = try gfx_loader.commit();
    }
    return true;
}

fn updateGain(track: zengine.audio.Track, gain: f32) !void {
    if (track.gain() != gain) try track.setGain(gain);
}

fn updateSettings(settings: []const u32) !void {
    const path_c = zengine.c.SDL_GetPrefPath("xgallom", "cathode-run");
    if (path_c == null) {
        log.err("failed obtaining save path", .{});
        return error.PathFailed;
    }
    defer zengine.c.SDL_free(path_c);
    const path = try std.fs.path.join(
        allocators.scratch(),
        &.{ std.mem.span(path_c), "settings.bin" },
    );
    defer allocators.scratch().free(path);
    const file = try std.fs.createFileAbsolute(path, .{ .lock = .exclusive });
    defer file.close();
    var out_buf: [256]u8 = undefined;
    var writer = file.writer(&out_buf);
    const w = &writer.interface;
    try w.writeInt(usize, settings.len, .little);
    for (settings) |setting| try w.writeInt(u32, setting, .little);
    try w.flush();
}

fn readSettings(settings: []u32) !void {
    const path_c = zengine.c.SDL_GetPrefPath("xgallom", "cathode-run");
    if (path_c == null) {
        log.err("failed obtaining save path", .{});
        return error.PathFailed;
    }
    defer zengine.c.SDL_free(path_c);
    const path = try std.fs.path.join(
        allocators.scratch(),
        &.{ std.mem.span(path_c), "settings.bin" },
    );
    defer allocators.scratch().free(path);
    const file = std.fs.openFileAbsolute(path, .{ .lock = .shared }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    var out_buf: [256]u8 = undefined;
    var reader = file.reader(&out_buf);
    const r = &reader.interface;
    const len = r.takeInt(usize, .little) catch return;
    if (len != settings.len) return;
    for (settings) |*setting| setting.* = try r.takeInt(u32, .little);
}

fn render(self: *const Zengine) !void {
    self.ui.beginDraw();
    self.ui.drawMainMenuBar(.{
        .allocs_open = &allocs_window.is_open,
        .perf_open = &perf_window.is_open,
        .log_open = &log_window.is_open,
    });
    self.ui.drawDock();

    self.ui.draw(allocs_window.element(), &allocs_window.is_open);
    self.ui.draw(perf_window.element(), &perf_window.is_open);
    self.ui.draw(log_window.element(), &log_window.is_open);

    self.ui.endDraw();

    _ = try game_render.renderScreen(self.renderer, self.ui, &.{
        gfx_passes.render.interface(),
        vfx_pass.interface(),
    }, &gfx_fence);
}
