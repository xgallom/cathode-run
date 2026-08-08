const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.core);
const Allocator = std.mem.Allocator;

pub const cp437 = @import("core/cp437.zig");
pub const game = @import("core/game.zig");
pub const int = @import("core/int.zig");
pub const param = @import("core/param.zig");
pub const prng = @import("core/prng.zig");

pub const static = @import("core/static.zig");
pub const unit = @import("core/unit.zig");
pub const Scratch = @import("core/Scratch.zig");
pub const Txt = @import("core/Txt.zig");

pub const state = @import("core/state.zig");
const InputResult = state.InputResult;
const UIState = state.UIState;
const Frame = state.Frame;
const GameEntity = state.GameEntity;
const GameState = state.GameState;

pub const Options = struct {
    debug: bool = builtin.mode == .Debug,
    output_symbol_table: bool = false,
    random_seed: ?bool = null,
    allow_level_skip: ?bool = null,
    entity_capacity: usize = unit.KB(64).v,
    input_buf_length: usize = 33,
    sample_queue_length: usize = 32,
    music_queue_length: usize = 4,
    music_fade_in_ms: u64 = 250,
    movement_fade_in_ms: u64 = 67,
    movement_fade_out_ms: u64 = 16,
};

pub const cathode_run_options: Options = .{
    // .output_symbol_table = true,
    .random_seed = false,
    .allow_level_skip = true,
};

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .audio, .level = .info },
        .{ .scope = .core, .level = .info },
        .{ .scope = .cp437, .level = .info },
        .{ .scope = .game, .level = .info },
        .{ .scope = .int, .level = .info },
        .{ .scope = .main, .level = .info },
        .{ .scope = .platform, .level = .info },
        .{ .scope = .param, .level = .info },
        .{ .scope = .prng, .level = .info },
        .{ .scope = .read, .level = .info },
        .{ .scope = .scratch, .level = .info },
        .{ .scope = .static, .level = .info },
        .{ .scope = .txt, .level = .info },
        .{ .scope = .unit, .level = .info },
    },
};

pub fn transfer(self: *GameState, to: game.SessionState) !game.SessionState {
    if (self.session.state == to) {
        @branchHint(.likely);
        return to;
    }

    log.debug("transfer: {t} -> {t}", .{ self.session.state, to });
    switch (to) {
        .start => unreachable,
        .menu => {
            if (!int.flag.has(self.ui.state, UIState.one(.not_first_start))) {
                try self.music_queue.appendBounded(static.asset.music.menu);
                int.flag.set(&self.ui.state, UIState.one(.not_first_start));
            }
            int.flag.clr(&self.ui.state, UIState.one(.quit));
            self.ui.delay = 0;
            self.ui.start_out_delay = 0;
            self.session.state = .menu;
            return .menu;
        },
        .settings => {
            self.ui.delay = 0;
            self.ui.start_out_delay = 0;
            self.session.state = .settings;
            return .settings;
        },
        .init => {
            self.session.reset();
            self.entities.clearRetainingCapacity();
            return .init;
        },
        .intro => {
            self.reset();
            if (int.flag.has(self.ui.state, UIState.one(.key_down))) {
                int.flag.set(&self.ui.state, UIState.one(.waiting_release));
            } else {
                int.flag.clr(&self.ui.state, UIState.one(.waiting_release));
            }
            int.flag.set(&self.ui.state, UIState.one(.waiting_sound));
            self.ui.delay = 0;
            self.session.state = .intro;
            return .intro;
        },
        .running => {
            if (self.session.state == .paused) {
                self.session.state = .running;
                return .running;
            }
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.engine_idle });
            int.flag.set(&self.ui.state, UIState.one(.sound_engine_idle_on));
            try self.music_queue.appendBounded(static.asset.music.levels[0]);
            self.ui.input = game.Dir.none;
            self.ui.delay = 0;
            self.session.state = .running;
            return .running;
        },
        .paused => {
            self.session.state = .paused;
            return .paused;
        },
        .died, .quit => |s| {
            if (int.flag.has(self.ui.state, UIState.one(.key_down))) {
                int.flag.set(&self.ui.state, UIState.one(.waiting_release));
            } else {
                int.flag.clr(&self.ui.state, UIState.one(.waiting_release));
            }
            try self.sample_queue.appendBounded(.{ .stop = static.asset.sample.engine_idle });
            try self.sample_queue.appendBounded(.{ .stop = static.asset.sample.engine_x });
            try self.sample_queue.appendBounded(.{ .stop = static.asset.sample.engine_y });
            int.flag.clr(
                &self.ui.state,
                UIState.many(&.{ .sound_engine_idle_on, .sound_engine_x_on, .sound_engine_y_on }),
            );
            try self.music_queue.appendBounded(static.asset.music.menu);
            self.ui.delay = 0;
            self.session.state = s;
            return s;
        },
        .end => {
            self.session.state = .end;
            try self.music_queue.appendBounded(null);
            return .end;
        },
    }
}

pub fn update(self: *GameState) !game.SessionState {
    switch (self.session.state) {
        .start => return if (self.ui.delay >= static.delay.start) .menu else .start,
        .menu => return try updateMenu(self),
        .settings => return try updateSettings(self),
        .init => return try consumeInputs(self),
        .intro => return try updateIntro(self),
        .running => return try updateRunning(self),
        .paused => return try updatePaused(self),
        .died, .quit => return try updateScore(self),
        .end => return .end,
    }
}

pub fn render(self: *GameState, frame: *const Frame) !void {
    if (self.session.state == .paused) return;
    frame.clear();
    switch (self.session.state) {
        .start => frame.write(static.txt.start, static.clr.default, 0),
        .menu => try drawMenu(self, frame),
        .settings => try drawSettings(self, frame),
        .init => {},
        .intro => drawIntro(self, frame),
        .running => try drawRunning(self, frame),
        .paused => unreachable,
        .died, .quit => try drawScore(self, frame),
        .end => {},
    }
}

pub fn sleep(self: *GameState) u64 {
    const frames = switch (self.session.state) {
        .start => static.delay.start_frames,
        .running => int.map(
            u32,
            self.session.score,
            0,
            static.score.running_delay_end,
            self.settings.delay_running_max,
            self.settings.delay_running_min,
        ),
        else => 1,
    };
    if (self.session.state != .paused and self.ui.update_delay) {
        self.ui.delay += frames * static.delay.step;
    }
    return frames;
}

fn consumeInputs(self: *GameState) !game.SessionState {
    var input_len: usize = 0;
    for (self.input_buf) |in| {
        switch (in.event) {
            .none => break,
            .err => return error.InputFailed,
            .down => int.flag.set(&self.ui.state, UIState.one(.key_down)),
            .up => int.flag.clr(&self.ui.state, UIState.one(.key_down)),
            .query => {},
        }
        input_len += 1;
    }
    return if (input_len < self.input_buf.len - 1) .intro else .init;
}

fn updateMenu(self: *GameState) !game.SessionState {
    if (self.ui.start_out_delay != 0) {
        const out_delay = self.ui.start_out_delay;
        if (self.ui.delay >= out_delay + static.delay.menu_out) switch (self.ui.active_idx) {
            0 => return .init,
            1 => {
                self.ui.active_idx = 0;
                return .settings;
            },
            2 => return .end,
            else => unreachable,
        };
        return .menu;
    }

    for (self.input_buf) |in| switch (in.event) {
        .none => break,
        .err => return error.InputFailed,
        .down => {},
        .up => if (in.isKey(&static.key.down)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            if (self.ui.active_idx < static.txt.menu_options.len - 1) self.ui.active_idx += 1;
        } else if (in.isKey(&static.key.up)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            if (self.ui.active_idx > 0) self.ui.active_idx -= 1;
        } else if (in.isKey(&static.key.accept)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            self.ui.start_out_delay = @max(self.ui.delay, static.delay.menu_in);
        },
        .query => {},
    };

    return .menu;
}

fn updateSettings(self: *GameState) !game.SessionState {
    if (self.ui.start_out_delay != 0) {
        const out_delay = self.ui.start_out_delay;
        if (self.ui.delay >= out_delay + static.delay.settings_out) {
            self.ui.active_idx = 1;
            return .menu;
        }
        return .settings;
    }

    for (self.input_buf) |in| switch (in.event) {
        .none => break,
        .err => return error.InputFailed,
        .down => {},
        .up => if (in.isKey(&static.key.down)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            if (self.ui.active_idx < static.txt.settings_options.len - 1) self.ui.active_idx += 1;
        } else if (in.isKey(&static.key.up)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            if (self.ui.active_idx > 0) self.ui.active_idx -= 1;
        } else if (in.isKey(&static.key.left)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            const value = &self.ui.settings[self.ui.active_idx];
            if (value.* > 0) value.* -= 1;
        } else if (in.isKey(&static.key.right)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            const value = &self.ui.settings[self.ui.active_idx];
            const max: u32 = switch (self.ui.active_idx) {
                0, 1 => 2,
                2, 3, 4 => 10,
                else => unreachable,
            };
            if (value.* < max) value.* += 1;
        } else if (in.isKey(&static.key.accept)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            self.ui.start_out_delay = @max(self.ui.delay, static.delay.settings_in);
        },
        .query => {},
    };

    return .settings;
}

fn updateIntro(self: *GameState) !game.SessionState {
    if (self.ui.delay >= static.delay.intro) {
        return if (int.flag.has(self.ui.state, UIState.one(.quit))) .menu else .running;
    }

    for (self.input_buf) |in| switch (in.event) {
        .none => break,
        .err => return error.InputFailed,
        .down => int.flag.set(&self.ui.state, UIState.one(.key_down)),
        .up => {
            if (!int.flag.has(self.ui.state, UIState.one(.waiting_release))) {
                if (in.isKey(&static.key.quit)) {
                    if (int.flag.has(self.ui.state, UIState.one(.quit))) {
                        return .end;
                    } else {
                        int.flag.set(&self.ui.state, UIState.one(.quit));
                    }
                }
                int.flag.set(&self.ui.state, UIState.one(.skip));
                try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            }
            int.flag.clr(&self.ui.state, UIState.many(&.{ .key_down, .waiting_release }));
        },
        .query => {},
    };

    if (self.ui.delay > static.delay.intro_in and
        int.flag.has(self.ui.state, UIState.one(.skip)))
    {
        if (self.ui.delay < static.delay.intro_out_0) self.ui.delay = static.delay.intro_out_0;
        int.flag.clr(&self.ui.state, UIState.one(.skip));
    }

    if (self.ui.delay > static.delay.intro_out_sound_0 and
        int.flag.has(self.ui.state, UIState.one(.waiting_sound)))
    {
        if (!int.flag.has(self.ui.state, UIState.one(.quit))) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.woosh });
        }
        int.flag.clr(&self.ui.state, UIState.one(.waiting_sound));
    }

    return .intro;
}

const allow_level_skip = cathode_run_options.allow_level_skip orelse cathode_run_options.debug;
fn updateRunning(self: *GameState) !game.SessionState {
    self.session.score += 1;
    var score = self.session.score;

    for (self.input_buf, 0..) |in, n| switch (in.event) {
        .none => if (n == self.input_buf.len - 1) return error.InputBufferOverflow else break,
        .err => return error.InputFailed,
        .down => if (in.isKey(&static.key.up)) int.flag.set(
            &self.ui.input,
            game.Dir.one(.up),
        ) else if (in.isKey(&static.key.right)) int.flag.set(
            &self.ui.input,
            game.Dir.one(.right),
        ) else if (in.isKey(&static.key.down)) int.flag.set(
            &self.ui.input,
            game.Dir.one(.down),
        ) else if (in.isKey(&static.key.left)) int.flag.set(
            &self.ui.input,
            game.Dir.one(.left),
        ),
        .up => if (in.isKey(&static.key.accept)) {
            self.session.score -= 1;
            self.ui.input = game.Dir.none;
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            return .paused;
        } else if (in.isKey(&static.key.up)) int.flag.clr(
            &self.ui.input,
            game.Dir.one(.up),
        ) else if (in.isKey(&static.key.right)) int.flag.clr(
            &self.ui.input,
            game.Dir.one(.right),
        ) else if (in.isKey(&static.key.down)) int.flag.clr(
            &self.ui.input,
            game.Dir.one(.down),
        ) else if (in.isKey(&static.key.left)) int.flag.clr(
            &self.ui.input,
            game.Dir.one(.left),
        ) else if (in.isKey(&static.key.quit)) {
            // TODO: Animation
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.woosh });
            return .quit;
        } else if (in.isKey(&static.key.dbg_prev_lvl)) {
            if (comptime allow_level_skip) {
                const level = static.score.level(score);
                score = if (level > 2)
                    static.score.level_2
                else if (level > 1)
                    static.score.level_1
                else
                    1;
                self.session.score = score;
            }
        } else if (in.isKey(&static.key.db_next_lvl)) {
            if (comptime allow_level_skip) {
                const level = static.score.level(score);
                score = if (level < 1)
                    static.score.level_1
                else if (level < 2)
                    static.score.level_2
                else
                    static.score.level_3;
                self.session.score = score;
            }
        },
        .query => {},
    };

    var pp: game.Point.U = undefined;
    var has_x: i32 = 0;
    var has_y: i32 = 0;
    {
        pp = self.session.player_pos.u();
        const min = game.player_pos_min;
        const max = game.playerPosMax(self.session.size);
        const step = game.player_pos_step;

        if (int.flag.has(self.ui.input, game.Dir.one(.up)) and pp.y > min.y) {
            pp.y -= step.y;
            has_y += 1;
        }
        if (int.flag.has(self.ui.input, game.Dir.one(.right)) and pp.x < max.x) {
            pp.x += step.x;
            has_x += 1;
        }
        if (int.flag.has(self.ui.input, game.Dir.one(.down)) and pp.y < max.y) {
            pp.y += step.y;
            has_y -= 1;
        }
        if (int.flag.has(self.ui.input, game.Dir.one(.left)) and pp.x > min.x) {
            pp.x -= step.x;
            has_x -= 1;
        }
        self.session.player_pos = pp.i();
    }

    try self.advance();

    {
        log.debug(
            "score check: {} {} {} {}",
            .{ score -| pp.y, pp.x, self.road_left[pp.y], self.road_right[pp.y] },
        );
        if (pp.x < self.road_left[pp.y] or pp.x > self.road_right[pp.y]) {
            if (self.ui.input != game.Dir.none) {
                int.flag.set(&self.ui.state, UIState.one(.key_down));
            }
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.explosion });
            return .died;
        }
        if (score -| self.session.player_pos.u().y >= static.score.won_game) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.woosh });
            return .died;
        }

        if (has_x != 0 and !int.flag.has(self.ui.state, UIState.one(.sound_engine_x_on))) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.engine_x });
            int.flag.set(&self.ui.state, UIState.one(.sound_engine_x_on));
        } else if (has_x == 0 and int.flag.has(self.ui.state, UIState.one(.sound_engine_x_on))) {
            try self.sample_queue.appendBounded(.{ .stop = static.asset.sample.engine_x });
            int.flag.clr(&self.ui.state, UIState.one(.sound_engine_x_on));
        }

        if (has_y > 0 and !int.flag.has(self.ui.state, UIState.one(.sound_engine_y_on))) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.engine_y });
            int.flag.set(&self.ui.state, UIState.one(.sound_engine_y_on));
        } else if (has_y <= 0 and int.flag.has(self.ui.state, UIState.one(.sound_engine_y_on))) {
            try self.sample_queue.appendBounded(.{ .stop = static.asset.sample.engine_y });
            int.flag.clr(&self.ui.state, UIState.one(.sound_engine_y_on));
        }

        if (has_y < 0 and int.flag.has(self.ui.state, UIState.one(.sound_engine_idle_on))) {
            try self.sample_queue.appendBounded(.{ .stop = static.asset.sample.engine_idle });
            int.flag.clr(&self.ui.state, UIState.one(.sound_engine_idle_on));
        } else if (has_y >= 0 and
            !int.flag.has(self.ui.state, UIState.one(.sound_engine_idle_on)))
        {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.engine_idle });
            int.flag.set(&self.ui.state, UIState.one(.sound_engine_idle_on));
        }

        blk: {
            const y = score -| (pp.y + 1);
            if (has_y < 0 and has_x == 0) break :blk;
            if (y <= 1) break :blk;
            const mod: u32 = switch (has_y) {
                -1 => 3,
                0 => 2,
                1 => 1,
                else => unreachable,
            };
            if (score % mod == 0) {
                const level = static.score.level(y);
                try self.entities.appendBounded(.{
                    .state = GameEntity.State.default,
                    .pos = .{ .x = @intCast(pp.i().x - has_x), .y = y },
                    .parallax_y = 0, // TODO:
                    .sym = static.sym.pcl_engine,
                    .attr = static.clr.pcl_engine[level],
                });
            }
        }

        if (score == static.score.level_1) {
            try self.music_queue.appendBounded(static.asset.music.levels[1]);
        } else if (score == static.score.level_2) {
            try self.music_queue.appendBounded(static.asset.music.levels[2]);
        }
    }
    return .running;
}

fn updatePaused(self: *GameState) !game.SessionState {
    for (self.input_buf) |in| switch (in.event) {
        .none => break,
        .err => return error.InputFailed,
        .down => int.flag.set(&self.ui.state, UIState.one(.key_down)),
        .up => if (in.isKey(&static.key.accept)) {
            try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            return .running;
        },
        .query => {},
    };

    return .paused;
}

fn updateScore(self: *GameState) !game.SessionState {
    if (self.ui.delay >= static.delay.score) {
        return if (int.flag.has(self.ui.state, UIState.one(.quit))) .end else .menu;
    }

    for (self.input_buf) |in| switch (in.event) {
        .none => break,
        .err => return error.InputFailed,
        .down => int.flag.set(&self.ui.state, UIState.one(.key_down)),
        .up => {
            if (!int.flag.has(self.ui.state, UIState.one(.waiting_release))) {
                if (in.isKey(&static.key.quit)) {
                    if (int.flag.has(self.ui.state, UIState.one(.quit))) {
                        return .end;
                    } else {
                        int.flag.set(&self.ui.state, UIState.one(.quit));
                    }
                }
                int.flag.set(&self.ui.state, UIState.one(.skip));
                try self.sample_queue.appendBounded(.{ .start = static.asset.sample.activate });
            }
            int.flag.clr(&self.ui.state, UIState.many(&.{ .key_down, .waiting_release }));
        },
        .query => {},
    };

    if (int.flag.has(self.ui.state, UIState.one(.skip))) {
        if (self.ui.delay < static.delay.score_out_0) self.ui.delay = static.delay.score_out_0;
        int.flag.clr(&self.ui.state, UIState.one(.skip));
    }

    return self.session.state;
}

fn drawMenu(self: *GameState, frame: *const Frame) !void {
    const sdelay = static.delay;
    const clr = static.clr;
    const stxt = static.txt;
    const height_full: i32 = @intCast(self.session.heightFull());
    const menu_y = 10;
    const size = self.session.size;
    const sizei = size.i();
    const fdelay: f32 = @floatFromInt(self.ui.delay);
    if (self.ui.delay < sdelay.menu_in) {
        const t = param.ease(.se, 3, param.invLerp(0, sdelay.menu_in, fdelay));
        var y_max: u32 = @intFromFloat(@round(
            param.lerp(0, @floatFromInt(height_full), param.sat(param.invLerp(0, 0.4, t))),
        ));
        frame.write(stxt.menu_bg[0 .. size.x * y_max], clr.menu_bg, 0);

        const txt_t = param.sat(param.invLerp(0.4, 1, t));
        var msg: []const u8 = stxt.menu_title;
        var msg_y: u32 = menu_y;
        var len: i32 = @intFromFloat(@round(param.lerp(0, @floatFromInt(msg.len), txt_t)));
        frame.write(
            msg[0..@intCast(len)],
            clr.menu_title,
            int.idx2D(msg_y, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
        y_max = @intFromFloat(@round(param.lerp(0, @floatFromInt(stxt.menu_options.len), txt_t)));
        msg_y = menu_y + 6;
        for (stxt.menu_options[0..y_max], 0..) |option, n| {
            msg = option;
            len = @intCast(msg.len);
            frame.write(
                msg[0..@intCast(len)],
                if (n == self.ui.active_idx) clr.menu_active else clr.menu_item,
                int.idx2D(msg_y + n, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
            );
        }
    } else if (self.ui.start_out_delay != 0) {
        const delay_out_0 = self.ui.start_out_delay;
        const t = param.ease(.s, 3, param.invLerp(
            @floatFromInt(delay_out_0),
            @floatFromInt(delay_out_0 + sdelay.menu_out - sdelay.step),
            fdelay,
        ));

        var y_max: u32 = @intFromFloat(@round(
            param.lerp(
                0,
                @floatFromInt(height_full),
                param.inv(param.sat(param.invLerp(0.6, 1, t))),
            ),
        ));
        frame.write(stxt.menu_bg[0 .. size.x * y_max], clr.menu_bg, 0);

        const txt_t = param.sat(param.invLerp(0, 0.6, t));
        var msg: []const u8 = stxt.menu_title;
        var msg_y: u32 = menu_y;
        var len: i32 = @as(i32, @intCast(msg.len)) - @as(i32, @intFromFloat(@round(
            param.lerp(0, @floatFromInt(msg.len), txt_t),
        )));
        frame.write(
            msg[0..@intCast(len)],
            clr.menu_title,
            int.idx2D(msg_y, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
        y_max = @as(u32, @intCast(stxt.menu_options.len)) - @as(u32, @intFromFloat(
            @round(param.lerp(0, @floatFromInt(stxt.menu_options.len), txt_t)),
        ));
        msg_y = menu_y + 6;
        for (stxt.menu_options[0..y_max], 0..) |option, n| {
            msg = option;
            len = @intCast(msg.len);
            frame.write(
                msg[0..@intCast(len)],
                if (n == self.ui.active_idx) clr.menu_active else clr.menu_item,
                int.idx2D(msg_y + n, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
            );
        }
    } else {
        frame.write(stxt.menu_bg, clr.menu_bg, 0);
        var msg: []const u8 = stxt.menu_title;
        var msg_y: u32 = menu_y;
        var len: i32 = @intCast(msg.len);
        frame.write(
            msg[0..@intCast(len)],
            clr.menu_title,
            int.idx2D(msg_y, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
        msg_y = menu_y + 6;
        for (stxt.menu_options, 0..) |option, n| {
            msg = option;
            len = @intCast(msg.len);
            frame.write(
                msg,
                if (n == self.ui.active_idx) clr.menu_active else clr.menu_item,
                int.idx2D(msg_y + n, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
            );
        }
    }
}

fn drawSettings(self: *GameState, frame: *const Frame) !void {
    const sdelay = static.delay;
    const clr = static.clr;
    const stxt = static.txt;
    const height_full: i32 = @intCast(self.session.heightFull());
    const menu_y = 10;
    const size = self.session.size;
    const sizei = size.i();
    const fdelay: f32 = @floatFromInt(self.ui.delay);
    if (self.ui.delay < sdelay.settings_in) {
        const t = param.ease(.se, 3, param.invLerp(0, sdelay.settings_in, fdelay));
        var y_max: u32 = @intFromFloat(@round(
            param.lerp(0, @floatFromInt(height_full), param.sat(param.invLerp(0, 0.4, t))),
        ));
        frame.write(stxt.menu_bg[0 .. size.x * y_max], clr.menu_bg, 0);

        const txt_t = param.sat(param.invLerp(0.4, 1, t));
        var msg: []const u8 = stxt.settings_title;
        var msg_y: u32 = menu_y;
        var len: i32 = @intFromFloat(@round(param.lerp(0, @floatFromInt(msg.len), txt_t)));
        frame.write(
            msg[0..@intCast(len)],
            clr.menu_title,
            int.idx2D(msg_y, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
        y_max = @intFromFloat(@round(
            param.lerp(0, @floatFromInt(stxt.settings_options.len), txt_t),
        ));
        msg_y = menu_y + 5;
        for (stxt.settings_options[0..y_max], 0..) |option, n| {
            msg = option;
            len = @intCast(msg.len);
            const x: u32 = @intCast(int.center(len + 19, sizei.x));
            frame.write(
                msg,
                if (n == self.ui.active_idx) clr.menu_active else clr.menu_item,
                int.idx2D(msg_y + n, x, size.x),
            );
            try drawSetting(self, frame, n, x);
        }
    } else if (self.ui.start_out_delay != 0) {
        const delay_out_0 = self.ui.start_out_delay;
        const t = param.ease(.s, 3, param.invLerp(
            @floatFromInt(delay_out_0),
            @floatFromInt(delay_out_0 + sdelay.settings_out - sdelay.step),
            fdelay,
        ));

        var y_max: u32 = @intFromFloat(@round(
            param.lerp(
                0,
                @floatFromInt(height_full),
                param.inv(param.sat(param.invLerp(0.6, 1, t))),
            ),
        ));
        frame.write(stxt.menu_bg[0 .. size.x * y_max], clr.menu_bg, 0);

        const txt_t = param.sat(param.invLerp(0, 0.6, t));
        var msg: []const u8 = stxt.settings_title;
        var msg_y: u32 = menu_y;
        var len: i32 = @as(i32, @intCast(msg.len)) - @as(i32, @intFromFloat(@round(
            param.lerp(0, @floatFromInt(msg.len), txt_t),
        )));
        frame.write(
            msg[0..@intCast(len)],
            clr.menu_title,
            int.idx2D(msg_y, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
        y_max = @as(u32, @intCast(stxt.settings_options.len)) - @as(u32, @intFromFloat(@round(
            param.lerp(0, @floatFromInt(stxt.settings_options.len), txt_t),
        )));
        msg_y = menu_y + 5;
        for (stxt.settings_options[0..y_max], 0..) |option, n| {
            msg = option;
            len = @intCast(msg.len);
            const x: u32 = @intCast(int.center(len + 19, sizei.x));
            frame.write(
                msg,
                if (n == self.ui.active_idx) clr.menu_active else clr.menu_item,
                int.idx2D(msg_y + n, x, size.x),
            );
            try drawSetting(self, frame, n, x);
        }
    } else {
        frame.write(stxt.menu_bg, clr.menu_bg, 0);
        var msg: []const u8 = stxt.settings_title;
        var msg_y: u32 = menu_y;
        var len: i32 = @intCast(msg.len);
        frame.write(
            msg[0..@intCast(len)],
            clr.menu_title,
            int.idx2D(msg_y, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
        msg_y = menu_y + 5;
        for (stxt.settings_options, 0..) |option, n| {
            msg = option;
            len = @intCast(msg.len);
            const x: u32 = @intCast(int.center(len + 19, sizei.x));
            frame.write(
                msg,
                if (n == self.ui.active_idx) clr.menu_active else clr.menu_item,
                int.idx2D(msg_y + n, x, size.x),
            );
            try drawSetting(self, frame, n, x);
        }
    }
}

fn drawSetting(self: *GameState, frame: *const Frame, n: usize, x: u32) !void {
    const clr = static.clr;
    const stxt = static.txt;
    const menu_y = 10;
    const size = self.session.size;
    const value = self.ui.settings[n];
    const x0 = x + 14;
    const attr_active = if (n == self.ui.active_idx) clr.menu_active_hl else clr.menu_item_hl;
    const attr_item = if (n == self.ui.active_idx) clr.menu_active else clr.menu_item;
    // "WIDE NORMAL NARROW"
    // "   SLOW NORMAL    "
    // "[0123456789  100% "
    const msg_y = menu_y + 5;
    switch (n) {
        0 => {
            frame.write(
                stxt.settings_widths[0],
                if (value == 0) attr_active else attr_item,
                int.idx2D(msg_y + n, x0, size.x),
            );
            frame.write(
                stxt.settings_widths[1],
                if (value == 1) attr_active else attr_item,
                int.idx2D(msg_y + n, x0 + stxt.settings_widths[0].len + 1, size.x),
            );
            frame.write(
                stxt.settings_widths[2],
                if (value == 2) attr_active else attr_item,
                int.idx2D(msg_y + n, x0 + stxt.settings_widths[0].len +
                    stxt.settings_widths[1].len + 2, size.x),
            );
        },
        1 => {
            frame.write(
                stxt.settings_game_speeds[0],
                if (value == 0) attr_active else attr_item,
                int.idx2D(msg_y + n, x0, size.x),
            );
            frame.write(
                stxt.settings_game_speeds[1],
                if (value == 1) attr_active else attr_item,
                int.idx2D(
                    msg_y + n,
                    x0 + stxt.settings_game_speeds[0].len + 1,
                    size.x,
                ),
            );
            frame.write(
                stxt.settings_game_speeds[2],
                if (value == 2) attr_active else attr_item,
                int.idx2D(
                    msg_y + n,
                    x0 + stxt.settings_game_speeds[0].len + stxt.settings_game_speeds[1].len + 2,
                    size.x,
                ),
            );
        },
        2, 3, 4 => {
            frame.fill(
                10,
                static.sym.empty_bar,
                attr_item,
                int.idx2D(msg_y + n, x0 + 1, size.x),
            );
            frame.fill(
                value,
                static.sym.full_bar,
                attr_active,
                int.idx2D(msg_y + n, x0 + 1, size.x),
            );
            const text = try self.scratch.print("{d:3}%", .{100 * value / 10});
            defer self.scratch.free(text);
            frame.write(text, attr_item, int.idx2D(msg_y + n, x0 + 12, size.x));
        },
        else => unreachable,
    }
}

fn drawIntro(self: *GameState, frame: *const Frame) void {
    const sdelay = static.delay;
    const clr = static.clr;
    const stxt = static.txt;
    const height_full: i32 = @intCast(self.session.heightFull());
    const intro_y = @divTrunc(height_full, 2);
    const size = self.session.size;
    const sizei = size.i();
    const fdelay: f32 = @floatFromInt(self.ui.delay);
    if (self.ui.delay < sdelay.intro_in) {
        const t = 2 * param.ease(.se, 3, param.invLerp(0, sdelay.intro_in, fdelay));
        var len: i32 = @intFromFloat(@round(param.lerp(0, stxt.intro.len, param.sat(t))));
        frame.write(
            stxt.intro[0..@intCast(len)],
            clr.intro,
            @intCast(int.idx2D(intro_y, int.center(len, sizei.x), sizei.x)),
        );
        len = @intFromFloat(@round(param.lerp(0, stxt.tutor.len, param.sat(t - 1))));
        frame.write(
            stxt.tutor[0..@intCast(len)],
            clr.intro,
            @intCast(int.idx2D(intro_y + 1, int.center(len, sizei.x), sizei.x)),
        );
    } else if (self.ui.delay >= sdelay.intro_out_0) {
        var t = 2 * param.inv(
            param.ease(.s, 3, param.invLerp(sdelay.intro_out_0, sdelay.intro, fdelay)),
        );
        var len: i32 = @intFromFloat(@round(param.lerp(0, stxt.intro.len, param.sat(t - 1))));
        frame.write(
            stxt.intro[0..@intCast(len)],
            clr.intro,
            @intCast(int.idx2D(intro_y, int.center(len, sizei.x), sizei.x)),
        );
        len = @intFromFloat(@round(param.lerp(0, stxt.tutor.len, param.sat(t))));
        frame.write(
            stxt.tutor[0..@intCast(len)],
            clr.intro,
            @intCast(int.idx2D(intro_y + 1, int.center(len, sizei.x), sizei.x)),
        );

        if (!int.flag.has(self.ui.state, UIState.one(.quit))) {
            const msg = stxt.msgs_running[0];
            const score = stxt.score;
            const score_num = stxt.score_num;
            t = 2 * param.ease(.se, 2, param.invLerp(sdelay.intro_out_0, sdelay.intro, fdelay));
            len = @intFromFloat(@round(param.lerp(0, msg.len, param.sat(t))));
            frame.write(
                msg[0..@intCast(len)],
                clr.txts[0],
                @intCast(int.idx2D(height_full - 2, 1, sizei.x)),
            );
            len = @intFromFloat(@round(param.lerp(0, score.len + score_num.len, param.sat(t - 1))));
            frame.write(
                score[0..@min(score.len, @as(u32, @intCast(len)))],
                clr.txts[0],
                @intCast(int.idx2D(height_full - 1, 1, sizei.x)),
            );
            frame.write(
                score_num[0..@as(u32, @intCast(len)) -| score.len],
                clr.score_nums[0],
                @intCast(int.idx2D(height_full - 1, 1 + @as(i32, @intCast(score.len)), sizei.x)),
            );
        }
    } else {
        frame.write(stxt.intro, clr.intro, int.idx2D(
            @as(u32, @intCast(intro_y)),
            int.center(stxt.intro.len, size.x),
            size.x,
        ));
        frame.write(stxt.tutor, clr.intro, int.idx2D(
            @as(u32, @intCast(intro_y + 1)),
            int.center(stxt.tutor.len, size.x),
            size.x,
        ));
    }
}

fn drawRunning(self: *GameState, frame: *const Frame) !void {
    const clr = static.clr;
    const stxt = static.txt;
    const height_full = self.session.heightFull();
    var score = self.session.score;
    const road_left = self.roadLeft();
    const road_right = self.roadRight();
    const map = self.symMap();
    const size = self.session.size;
    const pp = self.session.player_pos.u();
    const p_idx = pp.y * size.x + pp.x;

    {
        const yt: i32 = @intCast(score);
        const yb = yt -| size.i().y;
        var idx: usize = 0;
        while (idx < self.entities.items.len) : (idx += 1) {
            const entity = &self.entities.items[idx];
            if (!int.flag.has(entity.state, GameEntity.State.one(.exists))) continue;
            const score_y = entity.pos.i().y;
            const y_off = switch (entity.parallax_y) {
                0 => 0,
                else => int.Q(8).floor((yt - score_y) * entity.parallax_y),
            };
            if (score_y + y_off > yt) continue;
            if (score_y + y_off <= yb) continue;
            const y: u32 = @intCast(yt - (score_y + y_off));
            log.debug(
                "{} {} {} {} {} {}",
                .{ score, idx, score_y + y_off, y, entity.sym, y * size.x + entity.pos.x },
            );
            frame.set(
                entity.sym,
                entity.attr,
                y * size.x + entity.pos.x,
            );
        }
    }

    for (0..size.y) |y| {
        const x0 = y * size.x;
        const level = static.score.level(score -| y);
        frame.write(map[x0 .. x0 + road_left[y]], clr.walls[level], x0);
        // frame.write(
        //     map[x0 + road_left[y] .. x0 + road_right[y] + 1],
        //     clr.gnds[level],
        //     x0 + road_left[y],
        // );
        frame.write(
            map[x0 + road_right[y] + 1 .. x0 + size.x],
            clr.walls[level],
            x0 + road_right[y] + 1,
        );
    }

    log.debug("{} player {} {} {}", .{ score, pp.y, score -| pp.y, p_idx });
    score = score -| pp.y;
    const level = static.score.level(score);
    frame.set(static.sym.player, clr.gnds[level], p_idx);

    const score_num = try self.scratch.print("{d:04}", .{score});
    defer self.scratch.free(score_num);

    frame.write(stxt.msgs_running[level], clr.txts[level], int.idx2D(height_full - 2, 1, size.x));
    frame.write(stxt.score, clr.txts[level], int.idx2D(height_full - 1, 1, size.x));
    frame.write(
        score_num,
        clr.score_nums[level],
        int.idx2D(height_full - 1, 1 + stxt.score.len, size.x),
    );
}

fn drawScore(self: *GameState, frame: *const Frame) !void {
    const sdelay = static.delay;
    const clr = static.clr;
    const stxt = static.txt;
    const height_full: u16 = @intCast(self.session.heightFull());
    const size = self.session.size;
    const sizei = size.i();
    const msg_y = height_full / 2;
    const score = self.session.score -| self.session.player_pos.u().y;
    const level = static.score.level(score);
    const has_bg = self.session.state != .quit;
    const attr = if (self.session.state == .quit) clr.msgs_scores_quit else clr.msgs_scores[level];

    const txt_score = try self.scratch.print(
        "{s}{}{s}",
        .{
            stxt.scores[level][0],
            score,
            stxt.scores[level][1],
        },
    );
    defer self.scratch.free(txt_score);

    const fdelay: f32 = @floatFromInt(self.ui.delay);
    const msg = if (self.session.state == .quit) stxt.msg_quit else stxt.msgs_score[level];
    if (self.ui.delay < sdelay.score_in) {
        const t = param.ease(.se, 3, param.invLerp(0, sdelay.score_in, fdelay));

        if (has_bg) {
            const y_max: u32 = @intFromFloat(@round(
                param.lerp(0, @floatFromInt(height_full), param.sat(param.invLerp(0, 0.4, t))),
            ));
            frame.fill(size.x * y_max, static.sym.empty, attr, 0);
        }

        const msg_start: f32 = if (has_bg) 0.4 else 0.0;
        const score_start: f32 = if (has_bg) 0.7 else 0.5;
        var len: i32 = @intFromFloat(@round(
            param.lerp(0, @floatFromInt(msg.len), param.sat(
                param.invLerp(msg_start, score_start, t),
            )),
        ));
        frame.write(
            msg[0..@intCast(len)],
            attr,
            int.idx2D(msg_y, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
        len = @intFromFloat(@round(param.lerp(0, @floatFromInt(txt_score.len), param.sat(
            param.invLerp(score_start, 1, t),
        ))));
        frame.write(
            txt_score[0..@intCast(len)],
            attr,
            int.idx2D(msg_y + 1, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
    } else if (self.ui.delay >= sdelay.score_out_0) {
        const t = param.ease(.s, 3, param.invLerp(
            sdelay.score_out_0,
            sdelay.score - sdelay.step,
            fdelay,
        ));

        if (has_bg) {
            const y_max: u32 = @intFromFloat(@round(
                param.lerp(
                    0,
                    @floatFromInt(height_full),
                    param.inv(param.sat(param.invLerp(0.6, 1, t))),
                ),
            ));
            frame.fill(size.x * y_max, static.sym.empty, attr, 0);
        }

        const msg_end: f32 = if (has_bg) 0.3 else 0.5;
        const score_end: f32 = if (has_bg) 0.6 else 1.0;
        var len: i32 = @as(i32, @intCast(msg.len)) - @as(i32, @intFromFloat(@round(
            param.lerp(0, @floatFromInt(msg.len), param.sat(
                param.invLerp(0, msg_end, t),
            )),
        )));
        frame.write(
            msg[0..@intCast(len)],
            attr,
            int.idx2D(msg_y, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
        len = @as(i32, @intCast(txt_score.len)) - @as(i32, @intFromFloat(
            @round(param.lerp(0, @floatFromInt(txt_score.len), param.sat(
                param.invLerp(msg_end, score_end, t),
            ))),
        ));
        frame.write(
            txt_score[0..@intCast(len)],
            attr,
            int.idx2D(msg_y + 1, @as(u32, @intCast(int.center(len, sizei.x))), size.x),
        );
    } else {
        if (has_bg) frame.fill(size.x * height_full, static.sym.empty, attr, 0);
        frame.write(
            msg,
            attr,
            int.idx2D(msg_y, int.center(msg.len, size.x), size.x),
        );
        frame.write(
            txt_score,
            attr,
            int.idx2D(msg_y + 1, int.center(txt_score.len, size.x), size.x),
        );
    }
}
