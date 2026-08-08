const root = @import("root");
const options = root.cathode_run_options;
const std = @import("std");
const game = @import("game.zig");
const unit = @import("unit.zig");

pub const asset = struct {
    pub const music = struct {
        pub const levels = [_][]const u8{
            "level_0.mp3",
            "level_1.mp3",
            "level_2.mp3",
        };
        pub const menu = "menu.mp3";
    };
    pub const sample = struct {
        pub const activate = "activate.wav";
        pub const explosion = "explosion.wav";
        pub const woosh = "woosh.wav";
        pub const engine_idle = "engine_idle.wav";
        pub const engine_x = "engine_x.wav";
        pub const engine_y = "engine_y.wav";
    };
};

pub const gap_width = struct {
    pub const max = [_]i32{ 64, 64, 32 };
    pub const min = [_]i32{ 32, 18, 12 };
};

pub const score = struct {
    pub const level_1 = 3333;
    pub const level_2 = 6666;
    pub const level_3 = 9999;
    pub const won_game = 10000;

    pub const gap_width_end = 3333;
    pub const running_delay_end = 6666;

    pub fn level(score_v: u64) u32 {
        var acc: u32 = @intFromBool(score_v >= level_1);
        acc += @intFromBool(score_v >= level_2);
        acc += @intFromBool(score_v >= level_3);
        acc += @intFromBool(score_v >= won_game);
        return acc;
    }
};

pub const delay = struct {
    pub const start_frames = 17;
    pub const start = unit.s(1).v;
    pub const step = unit.us(16667).v;

    pub const menu_in = unit.ms(1000).v;
    pub const menu_out = unit.ms(1000).v;

    pub const settings_in = unit.ms(1000).v;
    pub const settings_out = unit.ms(1000).v;

    pub const intro = unit.s(10).v;
    pub const intro_in = unit.ms(1000).v;
    pub const intro_out = unit.ms(1000).v;
    pub const intro_out_0 = intro - intro_out;
    pub const intro_out_sound = unit.ms(750).v;
    pub const intro_out_sound_0 = intro - intro_out_sound;

    pub const running_max = [_]u64{ 4, 4, 3 };
    pub const running_min = [_]u64{ 4, 2, 1 };

    pub const score = unit.s(10).v;
    pub const score_in = unit.ms(1000).v;
    pub const score_out = unit.ms(1000).v;
    pub const score_out_0 = @This().score - score_out;
};

pub const ansi = struct {
    pub const cls = "\x1b[H\x1b[J";
    pub const clr_eol = "\x1b[K";
    pub const cur_rst = "\x1b[H";
    pub const cur_nl = "\x1b[B\x1b[G";
    pub const cur_pos = "\x1b[{d};{d}H";
    pub const cur_hide = "\x1b[?25l";
    pub const cur_show = "\x1b[?25h";

    pub const sync_start = "\x1b[?2026h";
    pub const sync_end = "\x1b[?2026l";
    pub const alt_scr_buf = "\x1b[?1049h";
    pub const alt_scr_buf_end = "\x1b[?1049l";
    pub const kbd_raw = "\x1b[>11u";
    pub const kbd_raw_end = "\x1b[<u";

    pub const query_pe = "\x1b[?u";
    pub const query_da = "\x1b[c";

    pub fn attr(ca: game.CellAttr) []const u8 {
        return attr_data[ca.bg][ca.fg];
    }

    pub fn attr24Bit(ca: game.CellAttr) []const u8 {
        return attr_data_24bit[ca.bg][ca.fg];
    }

    fn bg(v: u4) []const u8 {
        return if (v >= 8) "10" ++ &[_]u8{@as(u8, v & 0x7) + '0'} else "4" ++ &[_]u8{@as(u8, v) + '0'};
    }

    fn fg(v: u4) []const u8 {
        return if (v >= 8) "9" ++ &[_]u8{@as(u8, v & 0x7) + '0'} else "3" ++ &[_]u8{@as(u8, v) + '0'};
    }

    const attr_data = blk: {
        var result: [16][16][]const u8 = undefined;
        for (0..16) |b| {
            for (0..16) |f| {
                result[b][f] = "\x1b[0;" ++ bg(@intCast(b)) ++ ";" ++ fg(@intCast(f)) ++ "m";
            }
        }
        break :blk result;
    };

    fn bg24(v: [3][]const u8) []const u8 {
        return "48;2;" ++ v[0] ++ ";" ++ v[1] ++ ";" ++ v[2];
    }

    fn fg24(v: [3][]const u8) []const u8 {
        return "38;2;" ++ v[0] ++ ";" ++ v[1] ++ ";" ++ v[2];
    }

    const attr_data_24bit = blk: {
        const colors: [16][3][]const u8 = .{
            .{ "0", "0", "0" },
            .{ "170", "0", "0" },
            .{ "0", "170", "0" },
            .{ "170", "85", "0" },
            .{ "0", "0", "170" },
            .{ "170", "0", "170" },
            .{ "0", "170", "170" },
            .{ "170", "170", "170" },
            .{ "85", "85", "85" },
            .{ "255", "85", "85" },
            .{ "85", "255", "85" },
            .{ "255", "255", "85" },
            .{ "85", "85", "255" },
            .{ "255", "85", "255" },
            .{ "85", "255", "255" },
            .{ "255", "255", "255" },
        };

        var result: [16][16][]const u8 = undefined;
        for (0..16) |b| {
            for (0..16) |f| {
                result[b][f] = "\x1b[0;" ++ bg24(colors[b]) ++ ";" ++ fg24(colors[f]) ++ "m";
            }
        }
        break :blk result;
    };
};

pub const clr = struct {
    const C = game.Color;
    pub const default: game.CellAttr = .{ .fg = C.many(&.{ .red, .green, .blue }) };
    pub const menu_bg: game.CellAttr = .{ .fg = C.many(&.{ .red, .green, .blue }) };
    pub const menu_title: game.CellAttr = .{ .fg = C.many(&.{ .red, .green, .blue, .bold }) };
    pub const menu_item: game.CellAttr = .{ .fg = C.many(&.{ .red, .bold }) };
    pub const menu_active: game.CellAttr = .{ .fg = C.many(&.{ .red, .green, .bold }) };
    pub const menu_item_hl: game.CellAttr = .{ .fg = C.many(&.{ .red, .blue, .bold }) };
    pub const menu_active_hl: game.CellAttr = .{ .fg = C.many(&.{ .red, .green, .blue, .bold }) };
    pub const intro: game.CellAttr = .{ .fg = C.many(&.{ .red, .bold }) };
    pub const walls = [_]game.CellAttr{
        .{ .bg = C.one(.red), .fg = C.many(&.{ .red, .bold }) },
        .{ .bg = C.one(.green), .fg = C.many(&.{ .green, .bold }) },
        .{ .bg = C.one(.blue), .fg = C.many(&.{ .green, .blue }) },
        .{ .bg = C.many(&.{ .red, .green, .blue, .bold }), .fg = C.none },
        .{ .bg = C.none, .fg = C.many(&.{ .red, .green, .blue, .bold }) },
    };
    pub const gnds = [_]game.CellAttr{
        .{ .fg = C.many(&.{ .red, .green, .bold }) },
        .{ .fg = C.many(&.{ .green, .blue, .bold }) },
        .{ .fg = C.many(&.{ .red, .blue, .bold }) },
        .{ .bg = C.many(&.{ .red, .blue, .bold }), .fg = C.many(&.{ .red, .green, .blue, .bold }) },
        .{ .fg = C.many(&.{ .red, .green, .blue, .bold }) },
    };
    pub const pcl_engine = [_]game.CellAttr{
        .{ .fg = C.many(&.{ .red, .green }) },
        .{ .fg = C.many(&.{ .green, .blue }) },
        .{ .fg = C.many(&.{ .red, .blue }) },
        .{ .bg = C.many(&.{ .red, .blue, .bold }), .fg = C.many(&.{ .red, .green, .blue, .bold }) },
        .{ .fg = C.many(&.{ .red, .green, .blue }) },
    };
    pub const txts = [_]game.CellAttr{
        .{ .fg = C.many(&.{ .red, .bold }) },
        .{ .fg = C.many(&.{ .green, .bold }) },
        .{ .fg = C.many(&.{ .blue, .bold }) },
        .{ .fg = C.many(&.{ .red, .blue, .bold }) },
        .{ .fg = C.many(&.{ .red, .green, .blue, .bold }) },
    };
    pub const score_nums = [_]game.CellAttr{
        .{ .fg = C.many(&.{ .red, .green, .bold }) },
        .{ .fg = C.many(&.{ .blue, .bold }) },
        .{ .fg = C.many(&.{ .green, .blue, .bold }) },
        .{ .fg = C.many(&.{ .red, .green, .blue, .bold }) },
        .{ .fg = C.many(&.{ .red, .green, .blue, .bold }) },
    };
    pub const msgs_scores = [_]game.CellAttr{
        .{ .bg = C.none, .fg = C.many(&.{ .red, .bold }) },
        .{ .bg = C.none, .fg = C.many(&.{ .green, .bold }) },
        .{ .bg = C.one(.blue), .fg = C.many(&.{ .green, .blue, .bold }) },
        .{ .bg = C.many(&.{ .red, .green, .blue, .bold }), .fg = C.none },
        .{ .bg = C.many(&.{ .red, .green, .blue, .bold }), .fg = C.none },
    };
    pub const msgs_scores_quit: game.CellAttr = .{ .fg = C.many(&.{ .red, .bold }) };

    pub const rgb_f32: [16][3]f32 = .{
        .{ 0, 0, 0 },
        .{ 170.0 / 255.0, 0, 0 },
        .{ 0, 170.0 / 255.0, 0 },
        .{ 170.0 / 255.0, 85.0 / 255.0, 0 },
        .{ 0, 0, 170.0 / 255.0 },
        .{ 170.0 / 255.0, 0, 170.0 / 255.0 },
        .{ 0, 170.0 / 255.0, 170.0 / 255.0 },
        .{ 170.0 / 255.0, 170.0 / 255.0, 170.0 / 255.0 },
        .{ 85.0 / 255.0, 85.0 / 255.0, 85.0 / 255.0 },
        .{ 255.0 / 255.0, 85.0 / 255.0, 85.0 / 255.0 },
        .{ 85.0 / 255.0, 255.0 / 255.0, 85.0 / 255.0 },
        .{ 255.0 / 255.0, 255.0 / 255.0, 85.0 / 255.0 },
        .{ 85.0 / 255.0, 85.0 / 255.0, 255.0 / 255.0 },
        .{ 255.0 / 255.0, 85.0 / 255.0, 255.0 / 255.0 },
        .{ 85.0 / 255.0, 255.0 / 255.0, 255.0 / 255.0 },
        .{ 255.0 / 255.0, 255.0 / 255.0, 255.0 / 255.0 },
    };
};

pub const sym = struct {
    pub const empty = ' ';
    pub const gnd = ' ';
    pub const player = 0xE9;
    pub const void_stone = 0xF8;
    pub const pcl_engine = 0xFA;
    pub const empty_bar = 0xB0;
    pub const full_bar = 0xDB;
    pub const blocks = [_]u8{
        gnd,
        0xB0,
        0xB1,
        0xB2,
        0xDB,
    };
    pub const dbl_walls = [_]u8{
        gnd,
        gnd,
        gnd,
        0xC8,
        gnd,
        0xBA,
        0xC9,
        0xCC,
        gnd,
        0xBC,
        0xCD,
        0xCA,
        0xBB,
        0xB9,
        0xCB,
        0xCE,
    };

    pub fn dblWallsLookup(s: u8) game.Dir.Flags {
        return dbl_walls_lut[s];
    }

    const dbl_walls_lut = blk: {
        var lut: [256]game.Dir.Flags = @splat(0); // Default to 0
        lut[0xC8] = 0x3;
        lut[0xBA] = 0x5;
        lut[0xC9] = 0x6;
        lut[0xCC] = 0x7;
        lut[0xBC] = 0x9;
        lut[0xCD] = 0xA;
        lut[0xCA] = 0xB;
        lut[0xBB] = 0xC;
        lut[0xB9] = 0xD;
        lut[0xCB] = 0xE;
        lut[0xCE] = 0xF;
        break :blk lut;
    };
};

pub const txt = struct {
    pub const start = "Warming up energy coils...";
    pub const intro = "You are fleeing the fallen city...";

    pub const menu_title = "CATHODE RUN";
    pub const menu_options = [_][]const u8{
        "PLAY",
        "SETTINGS",
        "QUIT",
    };
    pub const menu_bg = @embedFile("menu_bg.txt");

    pub const settings_title = "SETTINGS";
    pub const settings_options = [_][]const u8{
        "GAP WIDTH    ",
        "GAME SPEED   ",
        "SOUND VOLUME ",
        "ENGINE VOLUME",
        "MUSIC VOLUME ",
    };
    pub const settings_widths = [_][]const u8{
        "WIDE",
        "NORMAL",
        "NARROW",
    };
    pub const settings_game_speeds = [_][]const u8{
        "SLOW",
        "NORMAL",
        "FAST",
    };

    pub const tutor = tjoin(&.{
        t3("W", "K", "\x18", "Up"),    ts,
        t3("S", "J", "\x19", "Down"),  ts,
        t3("A", "H", "\x1b", "Left"),  ts,
        t3("D", "L", "\x1a", "Right"), ts,
        t1("Q", "quit"),
    });

    pub const msgs_running = [_][]const u8{
        "You hear gunshots in the distance...",
        "She was only trouble, but you knew that from the start...",
        "Now all you see at night is her face...",
        "You know in your heart forgetting her is impossible.",
        "You know in your heart forgetting her is impossible.",
    };

    pub const msgs_score = [_][]const u8{
        "Will you keep trying? Better than dying forgotten...",
        "You keep trying. That's all that matters.",
        "Just keep trying. Let the chips fall where they may.",
        "And so you flew so close to the sun, you could almost touch it and burn.",
        "You may yet live to see a different life, free of their ever-present hunt.",
    };
    pub const msg_quit = "With this character's death, the thread of fate is severed.";

    pub const score = "SYSTEM ONLINE // SCORE: ";
    pub const score_num = "0000";
    pub const scores = [_][2][]const u8{
        .{ score_lost, "" },
        .{ score_lost, "" },
        .{ score_lost, "" },
        .{ score_lost, "" },
        .{ "// YOU OUTRAN THE VOID // FINAL SCORE: ", " //" },
    };

    const score_lost = "SIGNAL LOST // FINAL SCORE: ";
    const ts = " / ";

    fn t3(k1: []const u8, k2: []const u8, k3: []const u8, name: []const u8) []const u8 {
        return t1(k1 ++ "|" ++ k2 ++ "|" ++ k3, name);
    }

    fn t1(k: []const u8, name: []const u8) []const u8 {
        return "(" ++ k ++ ") " ++ name;
    }

    fn tjoin(comptime strs: []const []const u8) []const u8 {
        return comptime blk: {
            var acc: []const u8 = &.{};
            for (strs) |str| acc = acc ++ str;
            break :blk acc;
        };
    }

    pub const dbg_table = &dbg_table_data ++ "\n" ++
        "\xB0\xB0\xB0\n" ++
        "\xB0\xB0\xB0\n" ++
        "\xB0\xB0\xB0\n" ++
        "\xB1\xB1\xB1\n" ++
        "\xB1\xB1\xB1\n" ++
        "\xB1\xB1\xB1\n" ++
        "\xB2\xB2\xB2\n" ++
        "\xB2\xB2\xB2\n" ++
        "\xB2\xB2\xB2\n" ++
        "\xDB\xDB\xDB\n" ++
        "\xDB\xDB\xDB\n" ++
        "\xDB\xDB\xDB\n";
    const dbg_table_data = blk: {
        var result: [256 + 8]u8 = @splat(0);
        var n: usize = 0;
        var offset: usize = 0;
        while (n < 256) : (n += 1) {
            result[offset] = @intCast(n);
            if (n > 0 and n % 32 == 0) {
                offset += 1;
                result[offset] = '\n';
            }
            offset += 1;
        }
        break :blk result;
    };
};

pub const key = struct {
    pub const up = [_]u32{ 'w', 'k', 'W', 'K', 0x40000052 };
    pub const right = [_]u32{ 'd', 'l', 'D', 'L', 0x4000004f };
    pub const down = [_]u32{ 's', 'j', 'S', 'J', 0x40000051 };
    pub const left = [_]u32{ 'a', 'h', 'A', 'H', 0x40000050 };
    pub const accept = [_]u32{ ' ', '\r' };
    pub const quit = [_]u32{ 'q', 'Q' };
    pub const dbg_prev_lvl = [_]u32{'['};
    pub const db_next_lvl = [_]u32{']'};
};
