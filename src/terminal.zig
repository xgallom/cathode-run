const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.main);
const Allocator = std.mem.Allocator;

const Assets = @import("Assets.zig");
const Platform = @import("platform/Terminal.zig");
const core = @import("core");
const static = core.static;

pub const cathode_run_options = core.cathode_run_options;
pub const std_options = core.std_options;

pub fn main() !void {
    var allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = allocator.deinit();
    const gpa = allocator.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const assets = try Assets.init(aa);

    var platform = try Platform.init(gpa);
    defer platform.deinit(gpa);

    var game: core.GameState = try .init(gpa, platform.win_size);
    defer game.deinit(gpa);

    var frames = [_]core.Frame{
        try .init(gpa, platform.win_size),
        try .init(gpa, platform.win_size),
    };
    defer for (&frames) |*frame| frame.deinit(gpa);

    // TODO: Signal handler to teardown on crash?
    try platform.setup();
    defer platform.teardown() catch |err| log.err("platform teardown failed: {t}", .{err});

    // TODO: To internal?
    if (cathode_run_options.output_symbol_table) {
        try game.txt.writeSyms(static.txt.dbg_table);
        try platform.write(&game.txt);
        return;
    }

    try platform.audio.loadSound(
        gpa,
        try assets.assetPath(.samples, static.asset.sample.activate),
        .oneshot,
    );
    try platform.audio.loadSound(
        gpa,
        try assets.assetPath(.samples, static.asset.sample.explosion),
        .oneshot,
    );
    try platform.audio.loadSound(
        gpa,
        try assets.assetPath(.samples, static.asset.sample.woosh),
        .oneshot,
    );

    try platform.audio.loadSound(
        gpa,
        try assets.assetPath(.samples, static.asset.sample.engine_idle),
        .movement,
    );
    try platform.audio.loadSound(
        gpa,
        try assets.assetPath(.samples, static.asset.sample.engine_x),
        .movement,
    );
    try platform.audio.loadSound(
        gpa,
        try assets.assetPath(.samples, static.asset.sample.engine_y),
        .movement,
    );

    for (&static.asset.music.levels) |level| try platform.audio.loadSound(
        gpa,
        try assets.assetPath(.music, level),
        .music,
    );
    try platform.audio.loadSound(
        gpa,
        try assets.assetPath(.music, static.asset.music.menu),
        .music,
    );

    var active_music: ?[:0]const u8 = null;
    defer if (active_music) |am| platform.audio.stopSound(am) catch {};

    var frame_idx: usize = 0;
    while (true) {
        const frame = &frames[frame_idx % frames.len];
        frame_idx += 1;
        frame.clear();

        _ = try platform.getInput(game.input_buf);
        const to = try core.update(&game);

        while (game.sample_queue.pop()) |cmd| switch (cmd) {
            .start => |sample| try platform.playSound(
                try assets.assetPath(.samples, sample),
            ),
            .stop => |sample| try platform.audio.stopSound(
                try assets.assetPath(.samples, sample),
            ),
        };
        if (game.music_queue.pop()) |music| {
            if (active_music) |am| try platform.audio.stopSound(am);
            if (music) |m| {
                const path = try assets.assetPath(.music, m);
                try platform.audio.playSound(path);
                active_music = path;
            } else active_music = null;
        }

        try core.render(&game, frame);
        try platform.renderFull(frame);

        try platform.sleep(core.sleep(&game));
        switch (try core.transfer(&game, to)) {
            .init => try platform.reset(game.session),
            .end => return,
            else => {},
        }
    }
}
