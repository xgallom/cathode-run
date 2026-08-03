const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.gen_menu_bg);
const Allocator = std.mem.Allocator;

const core = @import("core");
const game_render = @import("render.zig");

const int = core.int;
const Q = int.Q;
const sym = core.static.sym;
const Dir = core.game.Dir;
const w = game_render.cells[0];
const h = game_render.cells[1];
const pw = 36;
const ph = 15;

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = allocator.deinit();
    const gpa = allocator.allocator();

    var prng = core.prng.Batch.init;
    const map = try gpa.alloc(u8, game_render.cells[1] * game_render.cells[0]);
    defer gpa.free(map);
    @memset(map, sym.gnd);
    try generateHorizontalMidpoint(map, &prng);
    try generateVerticalMidpoint(map, &prng);
    try generateQuadrants(map, &prng);
    try generateFrame(map);

    // for (0..h) |y| map[y * w] = '\n';
    const stdout = std.fs.File.stdout();
    var stdout_buf: [256]u8 = undefined;
    var writer = stdout.writer(&stdout_buf);
    const wr = &writer.interface;
    try wr.writeAll(map);
    try wr.flush();
}

fn generateHorizontalMidpoint(map: []u8, prng: *core.prng.Batch) !void {
    const y = h / 2;
    const y_off = y * w;
    prng.seed(0, @intCast(y));
    var rng: core.prng.Row = undefined;
    prng.compact(&rng, 0);
    map[y_off + w / 2] = sym.dbl_walls[Dir.all];
    {
        var r = Dir.all;
        for (0..w / 2) |rx| {
            const x = w / 2 - rx - 1;
            var walls = Dir.none;
            const rng_p = rng.bound(Q(10).period);
            const rng_u = rng.bound(Q(10).period);
            const rng_l = rng.bound(Q(10).period);
            const rng_d = rng.bound(Q(10).period);
            const is_spawn = rng_p >= Q(10).midperiod;
            const is_r_left = int.flag.mask(r, Dir.one(.left));

            if (is_spawn or is_r_left != 0) {
                if (is_r_left != 0) int.flag.set(&walls, Dir.one(.right));
                if (rng_u >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.up));
                if (rng_d >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.down));
                if (rng_l >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.left));
                const is_override_m = Q(4).tu(walls & (walls -% 1) == 0);
                int.flag.set(&walls, Dir.many(&.{ .down, .up, .left }) & is_override_m);
            }
            map[y_off + x] = sym.dbl_walls[walls];
            r = walls;
        }
    }
    {
        var l = Dir.all;
        for (w / 2 + 1..w) |x| {
            var walls = Dir.none;
            const rng_p = rng.bound(Q(10).period);
            const rng_u = rng.bound(Q(10).period);
            const rng_r = rng.bound(Q(10).period);
            const rng_d = rng.bound(Q(10).period);
            const is_spawn = rng_p >= Q(10).midperiod;
            const is_l_right = int.flag.mask(l, Dir.one(.right));
            if (is_spawn or is_l_right != 0) {
                if (is_l_right != 0) int.flag.set(&walls, Dir.one(.left));
                if (rng_u >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.up));
                if (rng_d >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.down));
                if (rng_r >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.right));
                const is_override_m = Q(4).tu(walls & (walls -% 1) == 0);
                int.flag.set(&walls, Dir.many(&.{ .down, .up, .right }) & is_override_m);
            }
            map[y_off + x] = sym.dbl_walls[walls];
            l = walls;
        }
    }
}

fn generateVerticalMidpoint(map: []u8, prng: *core.prng.Batch) !void {
    const x = w / 2;
    {
        var d = Dir.all;
        for (0..h / 2) |ry| {
            const y = h / 2 - ry - 1;
            const y_off = y * w;
            prng.seed(0, @intCast(y));
            var rng: core.prng.Row = undefined;
            prng.compact(&rng, 0);
            var walls = Dir.none;
            const rng_p = rng.bound(Q(10).period);
            const rng_u = rng.bound(Q(10).period);
            const rng_r = rng.bound(Q(10).period);
            const rng_l = rng.bound(Q(10).period);
            const is_spawn = rng_p >= Q(10).midperiod;
            const is_d_up = int.flag.mask(d, Dir.one(.up));

            if (is_spawn or is_d_up != 0) {
                if (is_d_up != 0) int.flag.set(&walls, Dir.one(.down));
                if (rng_u >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.up));
                if (rng_r >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.right));
                if (rng_l >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.left));
                const is_override_m = Q(4).tu(walls & (walls -% 1) == 0);
                int.flag.set(&walls, Dir.many(&.{ .up, .right, .left }) & is_override_m);
            }
            map[y_off + x] = sym.dbl_walls[walls];
            d = walls;
        }
    }
    {
        var u = Dir.all;
        for (h / 2 + 1..h) |y| {
            const y_off = y * w;
            prng.seed(0, @intCast(y));
            var rng: core.prng.Row = undefined;
            prng.compact(&rng, 0);
            var walls = Dir.none;
            const rng_p = rng.bound(Q(10).period);
            const rng_d = rng.bound(Q(10).period);
            const rng_r = rng.bound(Q(10).period);
            const rng_l = rng.bound(Q(10).period);
            const is_spawn = rng_p >= Q(10).midperiod;
            const is_u_down = int.flag.mask(u, Dir.one(.down));

            if (is_spawn or is_u_down != 0) {
                if (is_u_down != 0) int.flag.set(&walls, Dir.one(.up));
                if (rng_d >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.down));
                if (rng_r >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.right));
                if (rng_l >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.left));
                const is_override_m = Q(4).tu(walls & (walls -% 1) == 0);
                int.flag.set(&walls, Dir.many(&.{ .down, .right, .left }) & is_override_m);
            }
            map[y_off + x] = sym.dbl_walls[walls];
            u = walls;
        }
    }
}

fn generateQuadrants(map: []u8, prng: *core.prng.Batch) !void {
    for (0..h / 2) |ry| {
        const y = h / 2 - ry - 1;
        const y_off = y * w;
        prng.seed(0, @intCast(y));
        var rng: core.prng.Row = undefined;
        prng.compact(&rng, 0);
        {
            var r = sym.dblWallsLookup(map[y_off + w / 2]);
            for (0..w / 2) |rx| {
                const x = w / 2 - rx - 1;
                const d = sym.dblWallsLookup(map[y_off + x + w]);
                var walls = Dir.none;
                const rng_p = rng.bound(Q(10).period);
                const rng_u = rng.bound(Q(10).period);
                const rng_l = rng.bound(Q(10).period);
                const is_spawn = rng_p >= Q(10).midperiod;
                const is_r_left = int.flag.mask(r, Dir.one(.left));
                const is_d_up = int.flag.mask(d, Dir.one(.up));

                if (is_spawn or is_r_left != 0 or is_d_up != 0) {
                    if (is_r_left != 0) int.flag.set(&walls, Dir.one(.right));
                    if (is_d_up != 0) int.flag.set(&walls, Dir.one(.down));
                    if (rng_u >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.up));
                    if (rng_l >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.left));
                    const is_override_m = Q(4).tu(walls & (walls -% 1) == 0);
                    int.flag.set(&walls, Dir.many(&.{ .up, .left }) & is_override_m);
                }
                map[y_off + x] = sym.dbl_walls[walls];
                r = walls;
            }
        }
        {
            var l = sym.dblWallsLookup(map[y_off + w / 2]);
            for (w / 2 + 1..w) |x| {
                const d = sym.dblWallsLookup(map[y_off + x + w]);
                var walls = Dir.none;
                const rng_p = rng.bound(Q(10).period);
                const rng_u = rng.bound(Q(10).period);
                const rng_r = rng.bound(Q(10).period);
                const is_spawn = rng_p >= Q(10).midperiod;
                const is_l_right = int.flag.mask(l, Dir.one(.right));
                const is_d_up = int.flag.mask(d, Dir.one(.up));

                if (is_spawn or is_l_right != 0 or is_d_up != 0) {
                    if (is_l_right != 0) int.flag.set(&walls, Dir.one(.left));
                    if (is_d_up != 0) int.flag.set(&walls, Dir.one(.down));
                    if (rng_u >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.up));
                    if (rng_r >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.right));
                    const is_override_m = Q(4).tu(walls & (walls -% 1) == 0);
                    int.flag.set(&walls, Dir.many(&.{ .up, .right }) & is_override_m);
                }
                map[y_off + x] = sym.dbl_walls[walls];
                l = walls;
            }
        }
    }
    for (h / 2 + 1..h) |y| {
        const y_off = y * w;
        prng.seed(0, @intCast(y));
        var rng: core.prng.Row = undefined;
        prng.compact(&rng, 0);
        {
            var r = sym.dblWallsLookup(map[y_off + w / 2]);
            for (0..w / 2) |rx| {
                const x = w / 2 - rx - 1;
                const u = sym.dblWallsLookup(map[y_off + x - w]);
                var walls = Dir.none;
                const rng_p = rng.bound(Q(10).period);
                const rng_d = rng.bound(Q(10).period);
                const rng_l = rng.bound(Q(10).period);
                const is_spawn = rng_p >= Q(10).midperiod;
                const is_r_left = int.flag.mask(r, Dir.one(.left));
                const is_u_down = int.flag.mask(u, Dir.one(.down));

                if (is_spawn or is_r_left != 0 or is_u_down != 0) {
                    if (is_r_left != 0) int.flag.set(&walls, Dir.one(.right));
                    if (is_u_down != 0) int.flag.set(&walls, Dir.one(.up));
                    if (rng_d >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.down));
                    if (rng_l >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.left));
                    const is_override_m = Q(4).tu(walls & (walls -% 1) == 0);
                    int.flag.set(&walls, Dir.many(&.{ .down, .left }) & is_override_m);
                }
                map[y_off + x] = sym.dbl_walls[walls];
                r = walls;
            }
        }
        {
            var l = sym.dblWallsLookup(map[y_off + w / 2]);
            for (w / 2 + 1..w) |x| {
                const u = sym.dblWallsLookup(map[y_off + x - w]);
                var walls = Dir.none;
                const rng_p = rng.bound(Q(10).period);
                const rng_d = rng.bound(Q(10).period);
                const rng_r = rng.bound(Q(10).period);
                const is_spawn = rng_p >= Q(10).midperiod;
                const is_l_right = int.flag.mask(l, Dir.one(.right));
                const is_u_down = int.flag.mask(u, Dir.one(.down));

                if (is_spawn or is_l_right != 0 or is_u_down != 0) {
                    if (is_l_right != 0) int.flag.set(&walls, Dir.one(.left));
                    if (is_u_down != 0) int.flag.set(&walls, Dir.one(.up));
                    if (rng_d >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.down));
                    if (rng_r >= Q(10).midperiod) int.flag.set(&walls, Dir.one(.right));
                    const is_override_m = Q(4).tu(walls & (walls -% 1) == 0);
                    int.flag.set(&walls, Dir.many(&.{ .down, .right }) & is_override_m);
                }
                map[y_off + x] = sym.dbl_walls[walls];
                l = walls;
            }
        }
    }
}

fn generateFrame(map: []u8) !void {
    const sx = (w - pw) / 2;
    const sy = (h - ph) / 2;
    for (0..ph) |py| {
        for (0..pw) |px| {
            const y = sy + py;
            const y_off = y * w;
            const x = sx + px;
            map[y_off + x] = sym.gnd;
        }
    }
    {
        const y = sy;
        const y_off = y * w;
        for (0..pw) |px| {
            const x = sx + px;
            const u = sym.dblWallsLookup(map[y_off + x - w]);
            const is_u_down = int.flag.mask(u, Dir.one(.down));
            var walls = Dir.many(&.{ .left, .right });
            if (is_u_down != 0) int.flag.set(&walls, Dir.one(.up));
            map[y_off + x] = sym.dbl_walls[walls];
        }
    }
    {
        const y = sy + ph - 1;
        const y_off = y * w;
        for (0..pw) |px| {
            const x = sx + px;
            const d = sym.dblWallsLookup(map[y_off + x + w]);
            const is_d_up = int.flag.mask(d, Dir.one(.up));
            var walls = Dir.many(&.{ .left, .right });
            if (is_d_up != 0) int.flag.set(&walls, Dir.one(.down));
            map[y_off + x] = sym.dbl_walls[walls];
        }
    }
    {
        const y = sy + 4;
        const y_off = y * w;
        for (0..pw) |px| {
            const x = sx + px;
            map[y_off + x] = sym.dbl_walls[Dir.many(&.{ .left, .right })];
        }
    }
    {
        for (0..ph) |py| {
            const y = sy + py;
            const x = sx;
            const y_off = y * w;
            const l = sym.dblWallsLookup(map[y_off + x - 1]);
            const is_l_right = int.flag.mask(l, Dir.one(.right));
            var walls = Dir.many(&.{ .up, .down });
            if (is_l_right != 0) int.flag.set(&walls, Dir.one(.left));
            map[y_off + x] = sym.dbl_walls[walls];
        }
    }
    {
        for (0..ph) |py| {
            const y = sy + py;
            const x = sx + pw - 1;
            const y_off = y * w;
            const r = sym.dblWallsLookup(map[y_off + x + 1]);
            const is_r_left = int.flag.mask(r, Dir.one(.left));
            var walls = Dir.many(&.{ .up, .down });
            if (is_r_left != 0) int.flag.set(&walls, Dir.one(.right));
            map[y_off + x] = sym.dbl_walls[walls];
        }
    }
    {
        const y = sy;
        const x = sx;
        const y_off = y * w;
        const u = sym.dblWallsLookup(map[y_off + x - w]);
        const l = sym.dblWallsLookup(map[y_off + x - 1]);
        const is_u_down = int.flag.mask(u, Dir.one(.down));
        const is_l_right = int.flag.mask(l, Dir.one(.right));
        var walls = Dir.many(&.{ .down, .right });
        if (is_u_down != 0) int.flag.set(&walls, Dir.one(.up));
        if (is_l_right != 0) int.flag.set(&walls, Dir.one(.left));
        map[y_off + x] = sym.dbl_walls[walls];
    }
    {
        const y = sy;
        const x = sx + pw - 1;
        const y_off = y * w;
        const u = sym.dblWallsLookup(map[y_off + x - w]);
        const r = sym.dblWallsLookup(map[y_off + x + 1]);
        const is_u_down = int.flag.mask(u, Dir.one(.down));
        const is_r_left = int.flag.mask(r, Dir.one(.left));
        var walls = Dir.many(&.{ .down, .left });
        if (is_u_down != 0) int.flag.set(&walls, Dir.one(.up));
        if (is_r_left != 0) int.flag.set(&walls, Dir.one(.right));
        map[y_off + x] = sym.dbl_walls[walls];
    }
    {
        const y = sy + 4;
        const x = sx;
        const y_off = y * w;
        const l = sym.dblWallsLookup(map[y_off + x - 1]);
        const is_l_right = int.flag.mask(l, Dir.one(.right));
        var walls = Dir.many(&.{ .up, .down, .right });
        if (is_l_right != 0) int.flag.set(&walls, Dir.one(.left));
        map[y_off + x] = sym.dbl_walls[walls];
    }
    {
        const y = sy + 4;
        const x = sx + pw - 1;
        const y_off = y * w;
        const r = sym.dblWallsLookup(map[y_off + x + 1]);
        const is_r_left = int.flag.mask(r, Dir.one(.left));
        var walls = Dir.many(&.{ .up, .down, .left });
        if (is_r_left != 0) int.flag.set(&walls, Dir.one(.right));
        map[y_off + x] = sym.dbl_walls[walls];
    }
    {
        const y = sy + ph - 1;
        const x = sx;
        const y_off = y * w;
        const d = sym.dblWallsLookup(map[y_off + x + w]);
        const l = sym.dblWallsLookup(map[y_off + x - 1]);
        const is_d_up = int.flag.mask(d, Dir.one(.up));
        const is_l_right = int.flag.mask(l, Dir.one(.right));
        var walls = Dir.many(&.{ .up, .right });
        if (is_d_up != 0) int.flag.set(&walls, Dir.one(.down));
        if (is_l_right != 0) int.flag.set(&walls, Dir.one(.left));
        map[y_off + x] = sym.dbl_walls[walls];
    }
    {
        const y = sy + ph - 1;
        const x = sx + pw - 1;
        const y_off = y * w;
        const d = sym.dblWallsLookup(map[y_off + x + w]);
        const r = sym.dblWallsLookup(map[y_off + x + 1]);
        const is_d_up = int.flag.mask(d, Dir.one(.up));
        const is_r_left = int.flag.mask(r, Dir.one(.left));
        var walls = Dir.many(&.{ .up, .left });
        if (is_d_up != 0) int.flag.set(&walls, Dir.one(.down));
        if (is_r_left != 0) int.flag.set(&walls, Dir.one(.right));
        map[y_off + x] = sym.dbl_walls[walls];
    }
}
