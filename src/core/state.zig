const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const cathode_run_options = @import("root").cathode_run_options;

const game = @import("game.zig");
const int = @import("int.zig");
const prng = @import("prng.zig");
const Scratch = @import("Scratch.zig");
const static = @import("static.zig");
const Txt = @import("Txt.zig");

const log = std.log.scoped(.core);
pub const InputEvent = enum {
    none,
    err,
    down,
    up,
    query,
};

pub const InputResult = struct {
    event: InputEvent,
    keycode: u32 = 0,

    pub const QueryType = enum(u32) { pe = 1, da = 2 };

    pub const none: @This() = .{ .event = .none };
    pub const err: @This() = .{ .event = .err };

    pub fn down(keycode: u32) @This() {
        return .{ .event = .down, .keycode = keycode };
    }

    pub fn up(keycode: u32) @This() {
        return .{ .event = .up, .keycode = keycode };
    }

    pub fn query(query_type: QueryType) @This() {
        return .{ .event = .query, .keycode = @intFromEnum(query_type) };
    }

    pub fn queryType(self: @This()) QueryType {
        assert(self.event == .query);
        return @enumFromInt(self.keycode);
    }

    pub fn isKey(self: @This(), keys: []const u32) bool {
        return for (keys) |key| {
            if (key == self.keycode) break true;
        } else false;
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

    pub fn set(
        self: *const @This(),
        sym: u8,
        attr: game.CellAttr,
        idx: usize,
    ) void {
        assert(idx < self.syms.len);
        assert(self.syms.len == self.attrs.len);
        self.syms[idx] = sym;
        self.attrs[idx] = attr;
    }

    pub fn setSym(
        self: *const @This(),
        sym: u8,
        idx: usize,
    ) void {
        assert(idx < self.syms.len);
        self.syms[idx] = sym;
    }

    pub fn write(
        self: *const @This(),
        syms: []const u8,
        attr: game.CellAttr,
        idx: usize,
    ) void {
        assert(idx + syms.len <= self.syms.len);
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
        assert(idx + len <= self.syms.len);
        assert(self.syms.len == self.attrs.len);
        @memset(self.syms[idx .. idx + len], sym);
        @memset(self.attrs[idx .. idx + len], attr);
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        assert(self.syms.len == self.attrs.len);
        for (0..self.syms.len) |n| {
            try writer.print(
                "{}: {x:02} {x:02} {x:02}  ",
                .{ n, self.syms[n], self.attrs[n].bg, self.attrs[n].fg },
            );
            if (n % 16 == 0) try writer.writeByte('\n');
        }
    }
};

pub const UIState = enum {
    not_first_start,
    quit,
    skip,
    key_down,
    waiting_release,
    waiting_sound,
    sound_engine_idle_on,
    sound_engine_x_on,
    sound_engine_y_on,
    update_settings,

    const flags = int.Flags(@This());
    pub const Flags = flags.U;
    pub const none = flags.none;
    pub const one = flags.one;
    pub const many = flags.many;
};

pub const UISession = struct {
    settings: [5]u32 = .{ 1, 1, 6, 4, 7 },
    state: UIState.Flags = UIState.none,
    input: game.Dir.Flags = game.Dir.none,
    delay: u64 = 0,
    start_out_delay: u64 = 0,
    update_delay: bool = true,
    active_idx: u32 = 0,
};

pub const Settings = struct {
    gap_width_min: i32 = static.gap_width.min[1],
    gap_width_max: i32 = static.gap_width.max[1],
    delay_running_max: u32 = static.delay.running_max[1],
    delay_running_min: u32 = static.delay.running_min[1],
};

pub const GameEntity = struct {
    state: State.Flags = State.none,
    pos: game.Point.U,
    parallax_y: i32 = 0,
    sym: u8,
    attr: game.CellAttr,

    pub const State = enum {
        exists,

        const flags = int.Flags(@This());
        pub const Flags = flags.U;
        pub const none = flags.none;
        pub const default: Flags = one(.exists);
        pub const one = flags.one;
        pub const many = flags.many;
    };
};

pub const GameState = struct {
    settings: Settings = .{},
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
    entities: std.ArrayList(GameEntity),
    sample_queue: std.ArrayList(SampleCommand),
    music_queue: std.ArrayList(?[]const u8),

    pub const SampleCommand = union(enum) { start: []const u8, stop: []const u8 };

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
        const entities = try gpa.alloc(GameEntity, cathode_run_options.entity_capacity);
        errdefer gpa.free(entities);
        const sample_queue = try gpa.alloc(SampleCommand, cathode_run_options.sample_queue_length);
        errdefer gpa.free(sample_queue);
        const music_queue = try gpa.alloc(?[]const u8, cathode_run_options.music_queue_length);
        errdefer gpa.free(sample_queue);
        return .{
            .session = session,
            .scratch = scratch,
            .sym_map = sym_map.ptr,
            .road_left = road_left.ptr,
            .road_right = road_right.ptr,
            .row_rng = row_rng.ptr,
            .input_buf = input_buf,
            .entities = .initBuffer(entities),
            .sample_queue = .initBuffer(sample_queue),
            .music_queue = .initBuffer(music_queue),
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
        self.entities.deinit(gpa);
        self.sample_queue.deinit(gpa);
        self.music_queue.deinit(gpa);
        self.* = undefined;
    }

    pub fn reset(self: *@This()) void {
        // periods in Q20 (IA angle * Q10 period)
        // amplitudes in Q6
        // wave in Q20 (Q14 sin * Q6 amplitude)
        // 0.6 * sin(0.07 * t) + 0.4 * cos(0.03 * t)
        // target values for seed 0: 11682 5007 38 26
        self.settings.gap_width_max = static.gap_width.max[self.ui.settings[0]];
        self.settings.gap_width_min = static.gap_width.min[self.ui.settings[0]];
        self.settings.delay_running_max = @intCast(static.delay.running_max[self.ui.settings[1]]);
        self.settings.delay_running_min = @intCast(static.delay.running_min[self.ui.settings[1]]);
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
        // const wall = static.sym.dbl_walls[game.Dir.many(&.{ .up, .down })];
        for (0..self.session.size.y) |y| {
            self.road_left[y] = 0;
            self.road_right[y] = self.session.size.x - 1;
            // self.sym_map[y * self.session.size.x] = wall;
            // self.sym_map[(y + 1) * self.session.size.x - 1] = wall;
        }
    }

    pub fn advance(self: *@This()) !void {
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
        try self.generateGameRow();
    }

    // ------  ROAD  -----------
    // |_0   |      |          |_WIDTH - 1
    //       |      |
    //       |      |_ gap_pos + gap_width
    //       |      |_ road_right
    //       |
    //       |_ gap_pos
    //       |_ road_left

    pub fn generateGameRow(self: *@This()) !void {
        const sym = static.sym;
        const dblWallsLookup = sym.dblWallsLookup;
        const Dir = game.Dir;
        const Q = int.Q;

        const score = self.session.score;
        const size = self.session.size;
        const rng_idx = rngIdxForScore(score);

        const bounds = self.generateRoadBounds(score, rng_idx);
        // const next_bounds = self.generateRoadBounds(score + 1, rng_idx + 1);
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
            const obs_x = begin + obs_pos_rng % road_w;
            if (rng_obs < 8 + Q(10).round(score * 12 * road_w)) try self.entities.appendBounded(.{
                .state = GameEntity.State.default,
                .pos = .{ .x = obs_x, .y = score },
                .sym = sym.void_stone,
                .attr = static.clr.gnds[level],
            });
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

    pub fn generateRoadBounds(
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
            self.settings.gap_width_max,
            self.settings.gap_width_min,
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

    pub fn rngIdxForScore(score: u32) u32 {
        return score % (prng.Batch.len - 1);
    }

    pub fn symMap(self: *const @This()) []u8 {
        return self.sym_map[0..@intCast(self.session.size.area())];
    }

    pub fn roadLeft(self: *const @This()) []u32 {
        return self.road_left[0..self.session.size.y];
    }

    pub fn roadRight(self: *const @This()) []u32 {
        return self.road_right[0..self.session.size.y];
    }

    pub fn rowRng(self: *const @This()) []prng.Batch.U {
        return self.row_rng[0..self.session.size.x];
    }
};
