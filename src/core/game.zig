const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.game);
const Allocator = std.mem.Allocator;

const int = @import("int.zig");
const Txt = @import("Txt.zig");

pub const size_min: Point.U = .{ .x = 80, .y = 25 - status_height };
pub const size_max: Point.U = .{ .x = 800, .y = 250 - status_height };
pub const status_height = 3;
pub const player_start_height = 5;
pub const player_pos_min: Point.I = .{ .x = player_pos_step.x - 1, .y = player_pos_step.y - 1 };
pub const player_pos_step: Point.I = .{ .x = 1, .y = 1 };
pub const gap_pos_min = 2;
pub const max_crashes = 3;

pub fn playerPosMax(size: Point.U) Point.I {
    const size_i = size.i();
    return .{ .x = size_i.x - player_pos_step.x, .y = size_i.y - 1 - player_pos_step.y };
}

pub fn gapPosMax(size: Point.U, gap_width: u32) u32 {
    return size.x -| gap_width -| 2;
}

comptime {
    assert(size_max.x >= size_min.x);
    assert(size_max.y >= size_min.y);
    assert(size_min.y > player_start_height);
}

pub const Dir = enum {
    up,
    right,
    down,
    left,

    const flags = int.Flags(@This());
    pub const Flags = flags.U;
    pub const none = flags.none;
    pub const one = flags.one;
    pub const many = flags.many;
};

pub const Color = enum {
    red,
    green,
    blue,
    bold,

    const flags = int.Flags(@This());
    pub const Flags = flags.U;
    pub const none = flags.none;
    pub const one = flags.one;
    pub const many = flags.many;
};

pub const CellAttr = packed struct(u8) {
    bg: Color.Flags = Color.none,
    fg: Color.Flags = Color.none,

    pub const none: @This() = .{};

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("bg: {x:02}, fg: {x:02}", .{ self.bg, self.fg });
    }
};

pub const SessionState = enum(u32) {
    start,
    end,
    init,
    quit,
    died,
    intro,
    running,
    paused,
};

pub const Session = struct {
    size: Point.U,
    seed: u64 = 0,
    score: u32 = 0,
    state: SessionState = .start,
    player_pos: Point.I = .{},
    crahes: [max_crashes]u32 = @splat(0),

    pub fn init(win_size: Point.U) !@This() {
        // TODO: Resize?
        if (win_size.x < size_min.x or win_size.x > size_max.x or
            win_size.y < size_min.y + status_height)
        {
            log.err("get a reasonably sized device please", .{});
            return error.WrongSize;
        }
        const size: Point.U = .{
            .x = win_size.x,
            .y = @min(win_size.y - status_height, size_max.y),
        };
        return .{
            .size = size,
        };
    }

    pub fn reset(self: *@This()) void {
        self.score = 0;
        self.state = .init;
        self.player_pos = .i(.{
            .x = self.size.x / 2,
            .y = self.size.y - player_start_height,
        });
        self.crahes = @splat(0);
    }

    pub fn heightFull(self: *const @This()) u32 {
        return self.size.y + status_height;
    }
};

pub const PathConfig = struct {
    p1: u32,
    p2: u32,
    amp1: i32,
    amp2: i32,
};

pub const Point = struct {
    pub const U = extern struct {
        x: u32 = 0,
        y: u32 = 0,

        pub fn u(self: I) @This() {
            return .{ .x = @intCast(self.x), .y = @intCast(self.y) };
        }

        pub fn i(self: @This()) I {
            return .{ .x = @intCast(self.x), .y = @intCast(self.y) };
        }

        pub fn area(self: @This()) u64 {
            return self.x * self.y;
        }
    };

    pub const I = extern struct {
        x: i32 = 0,
        y: i32 = 0,

        pub fn i(self: U) @This() {
            return .{ .x = @intCast(self.x), .y = @intCast(self.y) };
        }

        pub fn u(self: @This()) U {
            return .{ .x = @intCast(self.x), .y = @intCast(self.y) };
        }
    };
};
