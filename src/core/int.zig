const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.int);

pub fn Int(comptime signedness: std.builtin.Signedness, comptime bits: comptime_int) type {
    return @Type(.{ .int = .{ .signedness = signedness, .bits = bits } });
}

pub fn center(inner: anytype, outer: anytype) @TypeOf(inner, outer) {
    return Q(1).round(outer - inner);
}

pub fn idx2D(y: anytype, x: anytype, w: anytype) @TypeOf(y, x, w) {
    return y * w + x;
}

pub fn clamp(x: anytype, x0: anytype, x1: anytype) @TypeOf(x, x0, x1) {
    return @min(@max(x, x0), x1);
}

// Bitwise select: y[n] = if (mask[n]) xt[n] else xf[n]
pub fn select(comptime T: type, xt: T, xf: T, mask: T) T {
    // assert(mask == std.math.maxInt(T) or mask == 0);
    return (xt & mask) | (xf & ~mask);
}

pub fn Flags(comptime E: type) type {
    const Indexer = std.enums.EnumIndexer(E);
    return struct {
        pub const U = Int(.unsigned, bits);
        pub const bits = Indexer.count;
        pub const none: U = 0;

        pub fn one(comptime e: E) U {
            return comptime @intCast(1 << Indexer.indexOf(e));
        }

        pub fn many(comptime es: []const E) U {
            return comptime blk: {
                var result = none;
                for (es) |e| result |= one(e);
                break :blk result;
            };
        }
    };
}

pub const flag = struct {
    pub fn mask(f: anytype, m: anytype) @TypeOf(f, m) {
        return f & m;
    }

    pub fn has(f: anytype, m: anytype) bool {
        return mask(f, m) == m;
    }

    pub fn only(f: anytype, m: anytype) bool {
        return mask(f, ~m) == 0;
    }

    pub fn is(f: anytype, m: anytype) bool {
        return f == m;
    }

    pub fn set(f_ptr: anytype, m: anytype) void {
        f_ptr.* |= m;
    }

    pub fn clr(f_ptr: anytype, m: anytype) void {
        f_ptr.* &= ~m;
    }
};

pub fn V(comptime N: comptime_int) type {
    return struct {
        pub const U = @Vector(len, Int(.unsigned, bits));
        pub const I = @Vector(len, Int(.signed, bits));
        pub const bits = N;
        pub const len = std.simd.suggestVectorLength(Int(.unsigned, N)) orelse
            @compileError("this was not anticipated");
    };
}

pub fn Q(comptime N: comptime_int) type {
    assert(N > 0);
    assert(N <= 32);
    return struct {
        pub const U = Int(.unsigned, bits);
        pub const I = Int(.signed, bits);
        const U2 = Int(.unsigned, bits * 2);
        const I2 = Int(.signed, bits * 2);
        pub const bits = N;
        pub const period = 1 << bits;
        pub const max: U = period - 1;
        pub const midperiod: U = 1 << (bits - 1);

        inline fn toI(val: anytype) I {
            const info = @typeInfo(@TypeOf(val)).int;
            const signed = info.signedness == .signed;
            return switch (comptime std.math.order(info.bits, bits)) {
                .gt => if (comptime signed) @truncate(val) else @intCast(@as(U, @truncate(val))),
                .lt => if (comptime signed) val else @intCast(val),
                .eq => if (comptime signed) val else @bitCast(val),
            };
        }

        // Is not zero mask
        pub fn nz(val: anytype) I {
            const exp = toI(val);
            // Sign extension
            return (exp | -%exp) >> bits - 1;
        }

        // Is zero mask
        pub fn z(val: anytype) I {
            return ~nz(val);
        }

        // Is true mask
        pub fn t(cond: bool) I {
            return nz(@intFromBool(cond));
        }

        // Is false mask
        pub fn nt(cond: bool) I {
            return z(@intFromBool(cond));
        }

        // Unsigned is not zero mask
        pub fn nzu(val: anytype) U {
            return @bitCast(nz(val));
        }

        // Unsigned is zero mask
        pub fn zu(val: anytype) U {
            return @bitCast(z(val));
        }

        // Unsigned is not zero mask
        pub fn tu(cond: bool) U {
            return @bitCast(t(cond));
        }

        // Unsigned is zero mask
        pub fn ntu(cond: bool) U {
            return @bitCast(nt(cond));
        }

        // Map x to <0;xr)
        pub fn bound(x: U, xr: U) U {
            return @intCast(@as(U2, x) * @as(U2, xr) >> bits);
        }

        // Map x to <y0;y1>
        pub fn range(x: U, y0: I, y1: I) I {
            assert(y1 >= y0);
            const xr = @as(I2, y1) - @as(I2, y0) + 1;
            const offset = @as(U2, x) * @as(U2, @intCast(xr)) >> bits;
            return @intCast(@as(I2, y0) + @as(I2, @intCast(offset)));
        }

        pub fn to(val: anytype) @TypeOf(val) {
            return val << bits;
        }

        pub fn mod(val: anytype) U {
            return @intCast(val & max);
        }

        /// Performs floor division
        pub fn floor(val: anytype) @TypeOf(val) {
            return val >> bits;
        }

        /// Performs rounded division
        pub fn round(val: anytype) @TypeOf(val) {
            return val + midperiod >> bits;
        }

        /// Performs ceiling division
        pub fn ceil(val: anytype) @TypeOf(val) {
            return val + max >> bits;
        }

        pub fn fromFloat(val: anytype) i64 {
            return @intFromFloat(@round(val * period));
        }
    };
}

pub const IA = struct {
    pub const @"90deg" = Q(8).period;
    pub const @"180deg" = Q(9).period;
    pub const @"270deg" = @"90deg" + @"180deg";
    pub const @"360deg" = Q(10).period;

    pub fn rad(comptime T: type, angle: anytype) T {
        const f: T = @floatFromInt(angle);
        return f * std.math.pi / @as(T, @floatFromInt(@"180deg"));
    }
};

pub fn pcgHash(comptime N: comptime_int, input: @Vector(N, u32)) @Vector(N, u32) {
    const U = @Vector(N, u32);
    const state = input *% @as(U, @splat(747796405)) +% @as(U, @splat(2891336453));
    const amt: @Vector(N, u5) = @intCast((state >> @as(U, @splat(28))) + @as(U, @splat(4)));
    const word = ((state >> amt) ^ state) *% @as(U, @splat(277803737));
    return (word >> @as(U, @splat(22))) ^ word;
}

fn Xoshiro128SSN(comptime N: comptime_int) type {
    assert(N > 0);
    return extern struct {
        state: [4]U,

        pub const U = @Vector(N, u32);
        pub const len = N;

        pub fn next(self: *@This()) U {
            const result = std.math.rotl(
                U,
                self.state[1] *% @as(U, @splat(5)),
                7,
            ) *% @as(U, @splat(9));
            const t = self.state[1] << @as(U, @splat(9));
            self.state[2] ^= self.state[0];
            self.state[3] ^= self.state[1];
            self.state[1] ^= self.state[2];
            self.state[0] ^= self.state[3];
            self.state[2] ^= t;
            self.state[3] ^= std.math.rotl(U, self.state[3], 11);
            return result;
        }
    };
}

pub const Xoshiro128SS = Xoshiro128SSN(1);
pub const Xoshiro128SSV = Xoshiro128SSN(V(32).len);

pub const Xoshiro256SS = extern struct {
    state: [4]u64,

    pub fn next(self: *@This()) u64 {
        const result = std.math.rotl(u32, self.state[1] *% 5, 7) *% 9;
        const t = self.state[1] << 17;
        self.state[2] ^= self.state[0];
        self.state[3] ^= self.state[1];
        self.state[1] ^= self.state[2];
        self.state[0] ^= self.state[3];
        self.state[2] ^= t;
        self.state[3] ^= std.math.rotl(u64, self.state[3], 45);
        return result;
    }
};

pub fn map(comptime T: type, x: T, xa: T, xb: T, ya: T, yb: T) T {
    const sign = @typeInfo(T).int.signedness;
    const bits = @typeInfo(T).int.bits;
    const T2 = Int(sign, bits * 2);
    const x0 = @min(xa, xb);
    const x1 = @max(xa, xb);
    const xr = x1 - x0;
    if (xr == 0) return ya;
    const y0 = @min(ya, yb);
    const y1 = @max(ya, yb);
    const yr: T2 = y1 - y0;
    const dx = clamp(x, x0, x1) - x0;
    const xp: T2 = select(T, dx, xr - dx, @bitCast(Q(bits).t(xb >= xa)));
    const yp: T = @intCast(@divTrunc(xp * yr, xr));
    const y = select(T, y0 + yp, y1 - yp, @bitCast(Q(bits).t(yb >= ya)));
    log.debug(
        "map: x: {}, xa: {}, xb: {}, ya: {}, yb: {},\n" ++
            "    xr: {}, yr: {}, dx: {}, xp: {}, yp: {}, y: {}",
        .{ x, xa, xb, ya, yb, xr, yr, dx, xp, yp, y },
    );
    return y;
}

pub fn sin(angle: anytype) i16 {
    // ABSOLUTE UNIT OF PREMATURE OPTIMIZATION
    const quadrant = Q(8).floor(angle);
    const idx: u8 = Q(8).mod(angle);
    const rev_idx: u8 = @truncate(@as(u16, IA.@"90deg") - idx);
    const is_rev_idx_m = Q(16).nzu(quadrant & 0x1);
    const is_neg_m = Q(16).nz(quadrant & 0x2);
    const is_idx_z_m = Q(16).zu(idx);
    const lookup = sin_lut[select(u8, rev_idx, idx, @truncate(is_rev_idx_m))];
    const result: i16 = select(u15, Q(14).period, lookup, @truncate(is_idx_z_m & is_rev_idx_m));
    return select(i16, -%result, result, is_neg_m);
}

pub fn cos(angle: anytype) i16 {
    return sin(angle +% IA.@"90deg");
}

const sin_lut: [Q(8).period]u15 = .{
    0,     101,   201,   302,   402,   503,   603,   704,
    804,   904,   1005,  1105,  1205,  1306,  1406,  1506,
    1606,  1706,  1806,  1906,  2006,  2105,  2205,  2305,
    2404,  2503,  2603,  2702,  2801,  2900,  2999,  3098,
    3196,  3295,  3393,  3492,  3590,  3688,  3786,  3883,
    3981,  4078,  4176,  4273,  4370,  4467,  4563,  4660,
    4756,  4852,  4948,  5044,  5139,  5235,  5330,  5425,
    5520,  5614,  5708,  5803,  5897,  5990,  6084,  6177,
    6270,  6363,  6455,  6547,  6639,  6731,  6823,  6914,
    7005,  7096,  7186,  7276,  7366,  7456,  7545,  7635,
    7723,  7812,  7900,  7988,  8076,  8163,  8250,  8337,
    8423,  8509,  8595,  8680,  8765,  8850,  8935,  9019,
    9102,  9186,  9269,  9352,  9434,  9516,  9598,  9679,
    9760,  9841,  9921,  10001, 10080, 10159, 10238, 10316,
    10394, 10471, 10549, 10625, 10702, 10778, 10853, 10928,
    11003, 11077, 11151, 11224, 11297, 11370, 11442, 11514,
    11585, 11656, 11727, 11797, 11866, 11935, 12004, 12072,
    12140, 12207, 12274, 12340, 12406, 12472, 12537, 12601,
    12665, 12729, 12792, 12854, 12916, 12978, 13039, 13100,
    13160, 13219, 13279, 13337, 13395, 13453, 13510, 13567,
    13623, 13678, 13733, 13788, 13842, 13896, 13949, 14001,
    14053, 14104, 14155, 14206, 14256, 14305, 14354, 14402,
    14449, 14497, 14543, 14589, 14635, 14680, 14724, 14768,
    14811, 14854, 14896, 14937, 14978, 15019, 15059, 15098,
    15137, 15175, 15213, 15250, 15286, 15322, 15357, 15392,
    15426, 15460, 15493, 15525, 15557, 15588, 15619, 15649,
    15679, 15707, 15736, 15763, 15791, 15817, 15843, 15868,
    15893, 15917, 15941, 15964, 15986, 16008, 16029, 16049,
    16069, 16088, 16107, 16125, 16143, 16160, 16176, 16192,
    16207, 16221, 16235, 16248, 16261, 16273, 16284, 16295,
    16305, 16315, 16324, 16332, 16340, 16347, 16353, 16359,
    16364, 16369, 16373, 16376, 16379, 16381, 16383, 16384,
};

// For reference:
fn generateSinLut() [Q(8).period]u15 {
    var result: [Q(8).period]u15 = undefined;
    for (0..Q(8).period) |n| {
        const t = IA.rad(f64, n);
        const y = @sin(t);
        const y14 = Q(14).fromFloat(y);
        result[n] = @intCast(y14);
    }
    return result;
}
