const std = @import("std");
const log = std.log.scoped(.audio);
const Allocator = std.mem.Allocator;

const root = @import("root");
const options = root.cathode_run_options;

const c = @cImport({
    @cInclude("miniaudio.h");
});

engine: *c.ma_engine,
sounds: std.StringArrayHashMapUnmanaged(Sound) = .empty,

const Sound = struct {
    config: SoundConfig,
    ptr: *c.ma_sound,
};

const SoundConfig = struct {
    behavior: union(enum) {
        imm,
        fade_in_out: struct { u64, u64 },
        fade_out: u64,
    } = .imm,
    play_mode: enum { oneshot, loop } = .oneshot,

    pub const music: @This() = .{
        .behavior = .{ .fade_in_out = .{ options.music_fade_in_ms, options.music_fade_in_ms } },
        .play_mode = .loop,
    };
    pub const oneshot: @This() = .{};
    pub const movement: @This() = .{
        .behavior = .{
            .fade_in_out = .{ options.movement_fade_in_ms, options.movement_fade_out_ms },
        },
        .play_mode = .loop,
    };
};

pub fn init(gpa: Allocator) !@This() {
    const self: @This() = .{ .engine = try gpa.create(c.ma_engine) };
    const result = c.ma_engine_init(null, self.engine);
    if (result != c.MA_SUCCESS) {
        log.err("engine init failed: {}", .{result});
        return error.AudioEngineFailed;
    }
    return self;
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    for (self.sounds.values()) |sound| {
        c.ma_sound_uninit(sound.ptr);
        gpa.destroy(sound.ptr);
    }
    self.sounds.deinit(gpa);
    c.ma_engine_uninit(self.engine);
    gpa.destroy(self.engine);
    self.* = undefined;
}

pub fn playSound(self: *@This(), path: [:0]const u8) !void {
    if (self.sounds.get(path)) |sound| {
        if (sound.config.behavior == .fade_in_out) {
            log.debug("set sound fade in 0 -> 1 {s}", .{path});
            const fade_in_ms = sound.config.behavior.fade_in_out.@"0";
            c.ma_sound_set_fade_in_milliseconds(sound.ptr, 0, 1, fade_in_ms);
        }
        log.debug("reset sound stop time {s}", .{path});
        c.ma_sound_reset_stop_time(sound.ptr);
        log.debug("seek sound to 0 {s}", .{path});
        var result = c.ma_sound_seek_to_pcm_frame(sound.ptr, 0);
        if (result != c.MA_SUCCESS) {
            log.err("failed seeking sound: {s} {}", .{ path, result });
            return error.AudioSoundStartFailed;
        }
        log.debug("start sound {s}", .{path});
        result = c.ma_sound_start(sound.ptr);
        if (result != c.MA_SUCCESS) {
            log.err("failed starting sound: {s} {}", .{ path, result });
            return error.AudioSoundStartFailed;
        }
    } else {
        log.err("sound not loaded: {s}", .{path});
        return error.AudioSoundNotLoaded;
    }
}

pub fn stopSound(self: *@This(), path: [:0]const u8) !void {
    if (self.sounds.get(path)) |sound| {
        log.debug("stop sound {s}", .{path});
        switch (sound.config.behavior) {
            .imm => {
                const result = c.ma_sound_stop(sound.ptr);
                if (result != c.MA_SUCCESS) {
                    log.err("failed stopping sound: {s} {}", .{ path, result });
                    return error.AudioSoundStopFailed;
                }
            },
            .fade_in_out => |fade| {
                const fade_out = fade.@"1";
                log.debug("set sound fade in -1 -> 0 {s}", .{path});
                c.ma_sound_set_fade_in_milliseconds(sound.ptr, -1, 0, fade_out);
                log.debug("set sound stop time {s}", .{path});
                c.ma_sound_set_stop_time_in_milliseconds(
                    sound.ptr,
                    c.ma_engine_get_time_in_milliseconds(self.engine) + fade_out,
                );
            },
            .fade_out => |fade_out| {
                log.debug("set sound fade in -1 -> 0 {s}", .{path});
                c.ma_sound_set_fade_in_milliseconds(sound.ptr, -1, 0, fade_out);
                log.debug("set sound stop time {s}", .{path});
                c.ma_sound_set_stop_time_in_milliseconds(
                    sound.ptr,
                    c.ma_engine_get_time_in_milliseconds(self.engine) + fade_out,
                );
            },
        }
    } else {
        log.err("sound not loaded: {s}", .{path});
        return error.AudioSoundNotLoaded;
    }
}

pub fn loadSound(
    self: *@This(),
    gpa: Allocator,
    path: [:0]const u8,
    comptime config: SoundConfig,
) !void {
    const sound: Sound = .{ .config = config, .ptr = try gpa.create(c.ma_sound) };
    errdefer gpa.destroy(sound.ptr);
    try self.sounds.putNoClobber(gpa, path, sound);
    const result = c.ma_sound_init_from_file(self.engine, path.ptr, 0, null, null, sound.ptr);
    if (result != c.MA_SUCCESS) {
        log.err("failed loading sound: {s} {}", .{ path, result });
        return error.AudioSoundLoadFailed;
    }
    if (config.play_mode == .loop) c.ma_sound_set_looping(sound.ptr, c.MA_TRUE);
}
