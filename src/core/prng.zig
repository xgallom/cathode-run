const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.prng);
const int = @import("int.zig");

pub const Batch = struct {
    prng: int.Xoshiro128SSV,

    pub const init: @This() = undefined;

    pub const U = int.Xoshiro128SSV.U;
    pub const len = int.Xoshiro128SSV.len;

    pub fn seed(self: *@This(), seed_u: u64, base_score: u32) void {
        const prng = &self.prng;
        const score_v: U = @as(U, @splat(base_score)) + std.simd.iota(u32, len);
        const seed_v: @Vector(len, u64) = @splat(seed_u);
        const base_low: U = @truncate(score_v ^ seed_v);
        const base_high: U = @truncate(score_v ^ (seed_v >> @as(U, @splat(32))));
        prng.state[0] = int.pcgHash(len, base_low ^ @as(U, @splat(0x4FC39540)));
        prng.state[1] = int.pcgHash(len, ~base_low ^ @as(U, @splat(0xBBAFA757)));
        prng.state[2] = int.pcgHash(len, base_high ^ @as(U, @splat(0xD091863C)));
        prng.state[3] = int.pcgHash(len, ~base_high ^ @as(U, @splat(0x71520635)));
        inline for (0..len) |n| log.debug("seed @{}, {x:016}: {x:08} {x:08} {x:08} {x:08}", .{
            score_v[n],
            seed_u,
            prng.state[0][n],
            prng.state[1][n],
            prng.state[2][n],
            prng.state[3][n],
        });
    }

    pub fn generate(self: *@This(), buf: []U) void {
        for (buf) |*y| y.* = self.prng.next();
    }

    pub fn compact(self: *const @This(), into: *Row, idx: u32) void {
        assert(idx < len);
        const state = &into.prng.state;
        for (0..4) |n| {
            const src: [len]u32 = self.prng.state[n];
            state[n] = @splat(src[idx]);
        }
        const sum = state[0] | state[1] | state[2] | state[3];
        if (sum[0] == 0) {
            @branchHint(.cold);
            state[0][0] = 0xBBC4774F;
            state[1][0] = 0x274BB948;
            state[2][0] = 0x6A36C8F4;
            state[3][0] = 0x7C7B31F4;
            log.warn("using default seed", .{});
        }
    }
};

pub const Row = struct {
    prng: int.Xoshiro128SS,

    // Q20 probability
    pub fn chance(probability: u32) bool {
        return bound(int.Q(20).period) >= probability;
    }

    pub fn bound(self: *@This(), period: u32) u32 {
        return int.Q(32).bound(self.prng.next()[0], period);
    }

    pub fn range(self: *@This(), lower: i32, upper: i32) i32 {
        return int.Q(32).range(self.prng.next()[0], lower, upper);
    }
};
