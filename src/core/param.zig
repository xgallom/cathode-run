const std = @import("std");
const assert = std.debug.assert;

pub fn inv(x: f32) f32 {
    return 1 - x;
}

pub fn lerp(y0: f32, y1: f32, t: f32) f32 {
    return inv(t) * y0 + t * y1;
}

pub fn invLerp(x0: f32, x1: f32, x: f32) f32 {
    return (x - x0) / (x1 - x0);
}

pub fn map(x: f32, x0: f32, x1: f32, y0: f32, y1: f32) f32 {
    return lerp(y0, y1, invLerp(x0, x1, x));
}

pub fn bound(x: f32, x1: f32) f32 {
    return @min(x, x1);
}

pub fn lbound(x: f32, x0: f32) f32 {
    return @max(x, x0);
}

pub fn clamp(x: f32, x0: f32, x1: f32) f32 {
    return lbound(bound(x, x1), x0);
}

pub fn sat(x: f32) f32 {
    return clamp(x, 0, 1);
}

pub fn npow(comptime N: comptime_int, f: f32) f32 {
    return switch (N) {
        1 => f,
        2 => f * f,
        3 => f * f * f,
        4 => f * f * f * f,
        5 => f * f * f * f * f,
        6 => f * f * f * f * f * f,
        7 => f * f * f * f * f * f * f,
        else => @compileError("unsupported npow degree"),
    };
}

pub const Ease = enum {
    s, // start
    e, // end
    se, // start -> end
    es, // end -> start
};

pub fn ease(comptime e: Ease, comptime N: comptime_int, t: f32) f32 {
    return switch (e) {
        .s => npow(N, t),
        .e => inv(npow(N, inv(t))),
        .se => lerp(ease(.s, N, t), ease(.e, N, t), t),
        .es => lerp(ease(.e, N, t), ease(.s, N, t), t),
    };
}
