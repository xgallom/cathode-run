const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.main);
const Allocator = std.mem.Allocator;

const Platform = @import("platform/Terminal.zig");
const core = @import("core");
const static = core.static;

pub const cathode_run_options = core.cathode_run_options;
pub const std_options = core.std_options;

pub fn main() !void {
    var allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = allocator.deinit();
    const gpa = allocator.allocator();

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

    var frame_idx: usize = 0;
    while (true) {
        const frame = &frames[frame_idx % frames.len];
        frame_idx += 1;
        frame.clear();

        _ = try platform.getInput(game.input_buf);
        const to = try core.update(&game);
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
