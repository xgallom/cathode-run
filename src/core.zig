const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.core);
const Allocator = std.mem.Allocator;

pub const game = @import("core/game.zig");
pub const int = @import("core/int.zig");
pub const param = @import("core/param.zig");
pub const prng = @import("core/prng.zig");
pub const static = @import("core/static.zig");
pub const unit = @import("core/unit.zig");
pub const Scratch = @import("core/Scratch.zig");
pub const Txt = @import("core/Txt.zig");

pub const Options = struct {
    debug: bool = builtin.mode == .Debug,
    output_symbol_table: bool = false,
    slow: bool = false,
    wide_gap: ?bool = null,
    random_seed: ?bool = null,
    allow_level_skip: ?bool = null,
    input_buf_length: usize = 33,
};

pub const cathode_run_options: Options = .{
    // .output_symbol_table = true,
    // .wide_gap = true,
    // .slow = true,
    // .random_seed = false,
    // .allow_level_skip = true,
};

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
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

pub const InputEvent = enum {
    none,
    err,
    down,
    up,
};

pub const InputResult = struct {
    event: InputEvent,
    keycode: i32 = 0,

    pub const none: @This() = .{ .event = .none };
    pub const err: @This() = .{ .event = .err };

    pub fn down(keycode: i32) @This() {
        return .{ .event = .down, .keycode = keycode };
    }

    pub fn up(keycode: i32) @This() {
        return .{ .event = .up, .keycode = keycode };
    }
};

pub const Frame = struct {
    syms: []u8,
    attrs: []game.CellAttr,
    duration: u64 = undefined,

    pub fn init(gpa: Allocator, win_size: game.Point.U) !@This() {
        const win_area: usize = @intCast(win_size.area());
        const syms = try gpa.alloc(u8, win_area);
        errdefer gpa.free(syms);
        const attrs = try gpa.alloc(game.CellAttr, win_area);
        errdefer gpa.free(attrs);
        @memset(syms, 0);
        @memset(attrs, .none);
        return .{ .syms = syms, .attrs = attrs };
    }

    pub fn deinit(self: *@This(), gpa: Allocator) void {
        gpa.free(self.syms);
        gpa.free(self.attrs);
    }

    pub fn txt(self: *const @This()) Txt {
        return .{ .head = self.syms.ptr, .tail = self.syms.ptr, .capacity = .B(self.syms.len) };
    }

    pub fn clear(self: *const @This()) void {
        @memset(self.syms, static.sym.empty);
        @memset(self.attrs, .none);
    }

    pub fn write(
        self: *const @This(),
        syms: []const u8,
        attr: game.CellAttr,
        idx: usize,
    ) void {
        assert(self.syms.len >= idx + syms.len);
        assert(self.syms.len == self.attrs.len);
        @memcpy(self.syms[idx .. idx + syms.len], syms);
        @memset(self.attrs[idx .. idx + syms.len], attr);
    }

    pub fn fill(
        self: *const @This(),
        len: usize,
        sym: u8,
        attr: game.CellAttr,
        idx: usize,
    ) void {
        assert(self.syms.len >= idx + len);
        assert(self.syms.len == self.attrs.len);
        @memset(self.syms[idx .. idx + len], sym);
        @memset(self.attrs[idx .. idx + len], attr);
    }
};

pub const UIState = enum {
    quit,
    skip,
    key_down,
    waiting_release,

    const flags = int.Flags(@This());
    pub const Flags = flags.U;
    pub const none = flags.none;
    pub const one = flags.one;
    pub const many = flags.many;
};

pub const UISession = struct {
    state: UIState.Flags = UIState.none,
    input: game.Dir.Flags = game.Dir.none,
    delay: u32 = 0,
};

pub fn transfer(self: *GameState, to: game.SessionState) !game.SessionState {
    if (self.session.state == to) return to;
    log.debug("transfer: {t} -> {t}", .{ self.session.state, to });
    switch (to) {
        .start => unreachable,
        .init => {
            self.session.reset();
            return .init;
        },
        .intro => {
            self.reset();
            if (int.flag.has(self.ui.state, UIState.one(.key_down))) {
                int.flag.set(&self.ui.state, UIState.one(.waiting_release));
            } else {
                int.flag.clr(&self.ui.state, UIState.one(.waiting_release));
            }
            self.ui.delay = 0;
            self.session.state = .intro;
            return .intro;
        },
        .running => {
            self.ui.input = game.Dir.none;
            self.session.state = .running;
            return .running;
        },
        .paused => unreachable,
        .died, .quit => |state| {
            if (int.flag.has(self.ui.state, UIState.one(.key_down))) {
                int.flag.set(&self.ui.state, UIState.one(.waiting_release));
            } else {
                int.flag.clr(&self.ui.state, UIState.one(.waiting_release));
            }
            self.ui.delay = 0;
            self.session.state = state;
            return state;
        },
        .end => {
            self.session.state = .end;
            return .end;
        },
    }
}

pub fn update(self: *GameState) !game.SessionState {
    switch (self.session.state) {
        .start => return .init,
        .init => return try consumeInputs(self),
        .intro => return try updateIntro(self),
        .running => return try updateRunning(self),
        .paused => unreachable,
        .died, .quit => return try updateScore(self),
        .end => return .end,
    }
}

pub fn render(self: *GameState, frame: *const Frame) !void {
    switch (self.session.state) {
        .start => frame.write(static.txt.start, static.clr.default, 0),
        .init => {},
        .intro => drawIntro(self, frame),
        .running => try drawRunning(self, frame),
        .paused => unreachable,
        .died, .quit => try drawScore(self, frame),
        .end => {},
    }
}

pub fn sleep(self: *GameState) u64 {
    switch (self.session.state) {
        .start => return static.delay.start,
        .running => return int.map(
            u32,
            self.session.score,
            0,
            static.score.running_delay_end,
            static.delay.running_max,
            static.delay.running_min,
        ),
        .intro, .died, .quit => self.ui.delay += static.delay.step,
        else => {},
    }
    return static.delay.step;
}

fn consumeInputs(self: *GameState) !game.SessionState {
    var input_len: usize = 0;
    for (self.input_buf) |input| {
        switch (input.event) {
            .none => break,
            .err => return error.InputFailed,
            .down => int.flag.set(&self.ui.state, UIState.one(.key_down)),
            .up => int.flag.clr(&self.ui.state, UIState.one(.key_down)),
        }
        input_len += 1;
    }
    return if (input_len < self.input_buf.len - 1) .intro else .init;
}

fn updateIntro(self: *GameState) !game.SessionState {
    if (self.ui.delay >= static.delay.intro) {
        return if (int.flag.has(self.ui.state, UIState.one(.quit))) .end else .running;
    }

    for (self.input_buf) |input| switch (input.event) {
        .none => break,
        .err => return error.InputFailed,
        .down => int.flag.set(&self.ui.state, UIState.one(.key_down)),
        .up => if (input.keycode != '\r') {
            if (!int.flag.has(self.ui.state, UIState.one(.waiting_release))) {
                if (input.keycode == static.key.quit) {
                    if (int.flag.has(self.ui.state, UIState.one(.quit))) {
                        return .end;
                    } else {
                        int.flag.set(&self.ui.state, UIState.one(.quit));
                    }
                }
                int.flag.set(&self.ui.state, UIState.one(.skip));
            }
            int.flag.clr(&self.ui.state, UIState.many(&.{ .key_down, .waiting_release }));
        },
    };

    if (self.ui.delay > static.delay.intro_in and
        int.flag.has(self.ui.state, UIState.one(.skip)))
    {
        if (self.ui.delay < static.delay.intro_out_0) self.ui.delay = static.delay.intro_out_0;
        int.flag.clr(&self.ui.state, UIState.one(.skip));
    }

    return .intro;
}

const allow_level_skip = cathode_run_options.allow_level_skip orelse cathode_run_options.debug;
fn updateRunning(self: *GameState) !game.SessionState {
    self.session.score += 1;
    if (self.session.score -| self.session.player_pos.u().y >= static.score.won_game) {
        return .died;
    }
    var score = self.session.score;

    for (self.input_buf, 0..) |input, n| switch (input.event) {
        .none => if (n == self.input_buf.len - 1) return error.InputBufferOverflow else break,
        .err => return error.InputFailed,
        .down => switch (input.keycode) {
            static.key.up[0], static.key.up[1] => int.flag.set(
                &self.ui.input,
                game.Dir.one(.up),
            ),
            static.key.right[0], static.key.right[1] => int.flag.set(
                &self.ui.input,
                game.Dir.one(.right),
            ),
            static.key.down[0], static.key.down[1] => int.flag.set(
                &self.ui.input,
                game.Dir.one(.down),
            ),
            static.key.left[0], static.key.left[1] => int.flag.set(
                &self.ui.input,
                game.Dir.one(.left),
            ),
            else => {},
        },
        .up => switch (input.keycode) {
            static.key.up[0], static.key.up[1] => int.flag.clr(
                &self.ui.input,
                game.Dir.one(.up),
            ),
            static.key.right[0], static.key.right[1] => int.flag.clr(
                &self.ui.input,
                game.Dir.one(.right),
            ),
            static.key.down[0], static.key.down[1] => int.flag.clr(
                &self.ui.input,
                game.Dir.one(.down),
            ),
            static.key.left[0], static.key.left[1] => int.flag.clr(
                &self.ui.input,
                game.Dir.one(.left),
            ),
            static.key.quit => {
                // TODO: Animation
                int.flag.set(&self.ui.state, UIState.one(.quit));
                return .quit;
            },
            static.key.dbg_prev_lvl => if (comptime allow_level_skip) {
                score = if (static.score.level(score) > 1) static.score.level_1 else 1;
                self.session.score = score;
            } else {},
            static.key.db_next_lvl => if (comptime allow_level_skip) {
                const level = static.score.level(score);
                score = if (level < 1)
                    static.score.level_1
                else if (level < 2)
                    static.score.level_2
                else {
                    self.session.score = static.score.won_game + self.session.player_pos.u().y;
                    return .died;
                };
                self.session.score = score;
            } else {},
            else => {},
        },
    };

    {
        var pp = self.session.player_pos.u();
        const min = game.player_pos_min;
        const max = game.playerPosMax(self.session.size);
        const step = game.player_pos_step;
        if (int.flag.has(self.ui.input, game.Dir.one(.up)) and pp.y > min.y) {
            pp.y -= step.y;
        }
        if (int.flag.has(self.ui.input, game.Dir.one(.right)) and pp.x < max.x) {
            pp.x += step.x;
        }
        if (int.flag.has(self.ui.input, game.Dir.one(.down)) and pp.y < max.y) {
            pp.y += step.y;
        }
        if (int.flag.has(self.ui.input, game.Dir.one(.left)) and pp.x > min.x) {
            pp.x -= step.x;
        }
        self.session.player_pos = pp.i();
        if (pp.x < self.road_left[pp.y] or pp.x > self.road_right[pp.y]) {
            if (self.ui.input != game.Dir.none) int.flag.set(&self.ui.state, UIState.one(.key_down));
            return .died;
        }
    }

    self.advance();
    return .running;
}

fn updateScore(self: *GameState) !game.SessionState {
    if (self.ui.delay >= static.delay.score) {
        return if (int.flag.has(self.ui.state, UIState.one(.quit))) .end else .init;
    }

    for (self.input_buf) |input| switch (input.event) {
        .none => break,
        .err => return error.InputFailed,
        .down => int.flag.set(&self.ui.state, UIState.one(.key_down)),
        .up => if (input.keycode != '\r') {
            if (!int.flag.has(self.ui.state, UIState.one(.waiting_release)) and
                self.ui.delay > static.delay.score_in)
            {
                if (input.keycode == static.key.quit) {
                    if (int.flag.has(self.ui.state, UIState.one(.quit))) {
                        return .end;
                    } else {
                        int.flag.set(&self.ui.state, UIState.one(.quit));
                    }
                }
                int.flag.set(&self.ui.state, UIState.one(.skip));
            }
            int.flag.clr(&self.ui.state, UIState.many(&.{ .key_down, .waiting_release }));
        },
    };

    if (int.flag.has(self.ui.state, UIState.one(.skip))) {
        if (self.ui.delay < static.delay.score_out_0) self.ui.delay = static.delay.score_out_0;
        int.flag.clr(&self.ui.state, UIState.one(.skip));
    }

    return self.session.state;
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

    const under_player = map[p_idx];
    map[p_idx] = static.sym.player;
    defer map[p_idx] = under_player;

    for (0..size.y) |y| {
        const x0 = y * size.x;
        const level = static.score.level(score -| y);
        frame.write(map[x0 .. x0 + road_left[y]], clr.walls[level], x0);
        frame.write(
            map[x0 + road_left[y] .. x0 + road_right[y] + 1],
            clr.gnds[level],
            x0 + road_left[y],
        );
        frame.write(
            map[x0 + road_right[y] + 1 .. x0 + size.x],
            clr.walls[level],
            x0 + road_right[y] + 1,
        );
    }

    score = score -| pp.y;
    const level = static.score.level(score);
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
    const has_bg = level >= 3;
    const attr = clr.msgs_scores[level];

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
        const t = param.ease(.s, 3, param.invLerp(sdelay.score_out_0, sdelay.score, fdelay));

        if (has_bg) {
            const y_max: u32 = @intFromFloat(@round(
                param.lerp(0, @floatFromInt(height_full), param.inv(param.sat(param.invLerp(0.6, 1, t)))),
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

pub const GameState = struct {
    ui: UISession = .{},
    session: *game.Session,
    prng: prng.Batch = .init,
    path: game.PathConfig = undefined,
    scratch: Scratch,
    sym_map: [*]u8,
    road_left: [*]u32,
    road_right: [*]u32,
    row_rng: [*]prng.Batch.U,
    input_buf: *[cathode_run_options.input_buf_length]InputResult,

    pub fn init(gpa: Allocator, win_size: game.Point.U) !@This() {
        const session = try gpa.create(game.Session);
        session.* = try .init(win_size);
        errdefer gpa.destroy(session);
        var scratch: Scratch = try .init(gpa);
        errdefer scratch.deinit(gpa);
        const sym_map = try gpa.alloc(u8, @intCast(session.size.area()));
        errdefer gpa.free(sym_map);
        const road_left = try gpa.alloc(u32, session.size.y);
        errdefer gpa.free(road_left);
        const road_right = try gpa.alloc(u32, session.size.y);
        errdefer gpa.free(road_right);
        const row_rng = try gpa.alloc(prng.Batch.U, session.size.x);
        errdefer gpa.free(row_rng);
        const input_buf = try gpa.create([cathode_run_options.input_buf_length]InputResult);
        errdefer gpa.destroy(input_buf);
        return .{
            .session = session,
            .scratch = scratch,
            .sym_map = sym_map.ptr,
            .road_left = road_left.ptr,
            .road_right = road_right.ptr,
            .row_rng = row_rng.ptr,
            .input_buf = input_buf,
        };
    }

    pub fn deinit(self: *@This(), gpa: Allocator) void {
        self.scratch.deinit(gpa);
        gpa.free(self.symMap());
        gpa.free(self.roadLeft());
        gpa.free(self.roadRight());
        gpa.free(self.rowRng());
        gpa.destroy(self.input_buf);
        gpa.destroy(self.session);
        self.* = undefined;
    }

    fn reset(self: *@This()) void {
        // periods in Q20 (IA angle + Q10 period)
        // amplitudes in Q6
        // wave in Q20 (Q14 sin + Q6 amplitude)
        // 0.6 * sin(0.07 * t) + 0.4 * cos(0.03 * t)
        // target values for seed 0: 11682 5007 38 26
        self.prng.seed(self.session.seed, self.session.score);
        var prng_r: prng.Row = undefined;
        self.prng.compact(&prng_r, rngIdxForScore(self.session.score));
        self.path.p1 = @intCast(prng_r.range(9349, 15449));
        self.path.p2 = @intCast(prng_r.range(3737, 5737));
        self.path.amp1 = prng_r.range(29, 57);
        self.path.amp2 = 64 - self.path.amp1;
        log.info(
            "path: {} {} {} {}",
            .{ self.path.p1, self.path.p2, self.path.amp1, self.path.amp2 },
        );
        @memset(self.symMap(), static.sym.gnd);
        const wall = static.sym.dbl_walls[game.Dir.many(&.{ .up, .down })];
        for (0..self.session.size.y) |y| {
            self.road_left[y] = 1;
            self.road_right[y] = self.session.size.x - 2;
            self.sym_map[y * self.session.size.x] = wall;
            self.sym_map[(y + 1) * self.session.size.x - 1] = wall;
        }
    }

    fn advance(self: *@This()) void {
        const score = self.session.score;
        const seed = self.session.seed;
        const size = self.session.size;
        log.debug("advance @{}", .{score});
        comptime assert(prng.Batch.len >= 2);
        if (rngIdxForScore(score) == 0) {
            self.prng.seed(seed, score);
            self.prng.generate(self.rowRng());
        }
        const sym_map = self.symMap();
        const road_left = self.roadLeft();
        const road_right = self.roadRight();
        @memmove(sym_map[size.x..], sym_map[0 .. sym_map.len - size.x]);
        @memmove(road_left[1..], road_left[0 .. road_left.len - 1]);
        @memmove(road_right[1..], road_right[0 .. road_right.len - 1]);
        self.generateGameRow();
    }

    // ------  ROAD  -----------
    // |_0   |      |          |_WIDTH - 1
    //       |      |
    //       |      |_ gap_pos + gap_width
    //       |      |_ road_right
    //       |
    //       |_ gap_pos
    //       |_ road_left

    fn generateGameRow(self: *@This()) void {
        const sym = static.sym;
        const dblWallsLookup = sym.dblWallsLookup;
        const Dir = game.Dir;
        const Q = int.Q;

        const score = self.session.score;
        const size = self.session.size;
        const rng_idx = rngIdxForScore(score);

        const bounds = self.generateRoadBounds(score, rng_idx);
        const next_bounds = self.generateRoadBounds(score + 1, rng_idx + 1);
        _ = next_bounds;
        const road_left = bounds.road_left;
        const road_right = bounds.road_right;
        self.road_left[0] = road_left;
        self.road_right[0] = road_right;
        const map = self.symMap();

        @memset(map[road_left .. road_right + 1], sym.gnd);

        const level = static.score.level(score);
        const lvl_scale = Q(8).to(1 + level);
        {
            const begin = road_left - 1;
            const end = 1;
            var walk = Dir.none;
            var x = begin;
            while (x >= end) : (x -= 1) {
                const dist = @min(begin -| x, 4);
                const r = walk;
                const d = dblWallsLookup(map[size.x + x]);
                var walls = Dir.none;
                const row_rng: [prng.Batch.len]u32 = self.row_rng[x];
                const rng = row_rng[rng_idx];
                const rng_p: u32 = Q(10).mod(rng);
                const is_spawn = Q(10).round(rng_p * lvl_scale) >= Q(10).midperiod;
                const is_d_up = int.flag.mask(d, Dir.one(.up));
                const is_r_left = int.flag.mask(r, Dir.one(.left));
                if (is_spawn | ((d | r) == Dir.none) | ((is_d_up | is_r_left) != 0)) {
                    const rng_u: u32 = Q(10).mod(rng >> Q(10).bits);
                    const rng_l: u32 = Q(10).mod(rng >> 2 * Q(10).bits);
                    const is_u_rng_m = Q(4).tu(Q(10).round(rng_u * dist * lvl_scale) >= 1297);
                    const is_l_rng_m = Q(4).tu(Q(10).round(rng_l * lvl_scale) >= 897);
                    const is_d_up_m = Q(4).nzu(is_d_up);
                    const is_r_left_m = Q(4).nzu(is_r_left);
                    int.flag.set(&walls, Dir.one(.up) & is_u_rng_m);
                    int.flag.set(&walls, Dir.one(.right) & is_r_left_m);
                    int.flag.set(&walls, Dir.one(.down) & is_d_up_m);
                    int.flag.set(&walls, Dir.one(.left) & is_l_rng_m);
                    const is_override_m = Q(4).tu((walls & (walls -% 1)) == 0);
                    int.flag.set(&walls, Dir.many(&.{ .up, .left }) & is_override_m);
                }
                map[x] = sym.dbl_walls[walls];
                walk = walls;
            }
            map[x] = sym.dbl_walls[
                Dir.many(&.{ .up, .down }) | int.select(u8, Dir.one(.right), Dir.none, Q(8).tu(
                    int.flag.has(walk, Dir.one(.left)),
                ))
            ];
        }
        {
            const begin = road_left;
            const end = road_right;
            const road_w = end + 1 - begin;
            const row_rng: [prng.Batch.len]u32 = self.row_rng[(end + begin) / 2];
            const rng = row_rng[rng_idx];
            const rng_obs = Q(8).mod(rng);
            const obs_pos_rng = Q(16).mod(rng >> Q(8).bits);
            const spawn_m = Q(8).tu(rng_obs < 8 + Q(10).round(score * 12 * road_w));
            const obs_x = begin + obs_pos_rng % road_w;
            map[obs_x] = int.select(u8, sym.void_stone, map[obs_x], spawn_m);
        }
        {
            const begin = road_right + 1;
            const end = size.x - 2;
            var walk = Dir.none;
            for (begin..end + 1) |x| {
                const dist = @min(x - begin, 4);
                const l = walk;
                const d = dblWallsLookup(map[size.x + x]);
                var walls = Dir.none;
                const row_rng: [prng.Batch.len]u32 = self.row_rng[x];
                const rng = row_rng[rng_idx];
                const rng_p: u32 = Q(10).mod(rng);
                const is_spawn = Q(10).round(rng_p * lvl_scale) >= Q(10).midperiod;
                const is_d_up = int.flag.mask(d, Dir.one(.up));
                const is_l_right = int.flag.mask(l, Dir.one(.right));
                if (is_spawn | ((d | l) == Dir.none) | ((is_d_up | is_l_right) != 0)) {
                    const rng_u: u32 = Q(10).mod(rng >> Q(10).bits);
                    const rng_r: u32 = Q(10).mod(rng >> 2 * Q(10).bits);
                    const is_u_rng_m = Q(4).tu(Q(10).round(rng_u * dist * lvl_scale) >= 1297);
                    const is_r_rng_m = Q(4).tu(Q(10).round(rng_r * lvl_scale) >= 897);
                    const is_d_up_m = Q(4).nzu(is_d_up);
                    const is_l_right_m = Q(4).nzu(is_l_right);
                    int.flag.set(&walls, Dir.one(.up) & is_u_rng_m);
                    int.flag.set(&walls, Dir.one(.right) & is_r_rng_m);
                    int.flag.set(&walls, Dir.one(.down) & is_d_up_m);
                    int.flag.set(&walls, Dir.one(.left) & is_l_right_m);
                    const is_override_m = Q(4).tu((walls & (walls -% 1)) == 0);
                    int.flag.set(&walls, Dir.many(&.{ .up, .right }) & is_override_m);
                }
                map[x] = sym.dbl_walls[walls];
                walk = walls;
            }
            map[end + 1] = sym.dbl_walls[
                Dir.many(&.{ .up, .down }) | int.select(u8, Dir.one(.left), Dir.none, Q(8).tu(
                    int.flag.has(walk, Dir.one(.right)),
                ))
            ];
        }
    }

    fn generateRoadBounds(
        self: *@This(),
        score: u32,
        idx: u32,
    ) struct { road_left: u32, road_right: u32 } {
        // TODO: Verify this behaves consistently between frames
        const Q = int.Q;
        const gap_width = int.map(
            i32,
            @intCast(score),
            0,
            static.score.gap_width_end,
            static.gap_width.max,
            static.gap_width.min,
        );
        var prng_r: prng.Row = undefined;
        self.prng.compact(&prng_r, idx);
        const skew = prng_r.bound(static.score.level(score) + 1);
        const gap_pos = blk: {
            const path = self.path;
            const wave = path.amp1 * int.sin(Q(10).mod(Q(10).round(score * path.p1))) +
                path.amp2 * int.cos(Q(10).mod(Q(10).round(score * path.p2)));
            const offset = Q(20).round(wave * 25);
            const center = @divTrunc(self.session.size.i().x, 2) + offset;
            const jitter = prng_r.range(-1, 1);
            const gap_pos = center - @divTrunc(gap_width - @as(i32, @intCast(skew)), 2) + jitter;
            break :blk int.clamp(
                gap_pos,
                game.gap_pos_min,
                game.gapPosMax(self.session.size, @intCast(gap_width)),
            );
        };
        const road_left: u32 = @as(u32, @intCast(gap_pos)) + skew;
        const road_right: u32 = @as(u32, @intCast(gap_pos)) + @as(u32, @intCast(gap_width)) - skew;
        log.debug(
            "road left: {}, road right: {}, gap_pos: {}, gap_width: {}",
            .{ road_left, road_right, gap_pos, gap_width },
        );
        return .{ .road_left = road_left, .road_right = road_right };
    }

    fn rngIdxForScore(score: u32) u32 {
        return score % (prng.Batch.len - 1);
    }

    fn symMap(self: *const @This()) []u8 {
        return self.sym_map[0..@intCast(self.session.size.area())];
    }

    fn roadLeft(self: *const @This()) []u32 {
        return self.road_left[0..self.session.size.y];
    }

    fn roadRight(self: *const @This()) []u32 {
        return self.road_right[0..self.session.size.y];
    }

    fn rowRng(self: *const @This()) []prng.Batch.U {
        return self.row_rng[0..self.session.size.x];
    }
};
