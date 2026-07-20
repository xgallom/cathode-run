const builtin = @import("builtin");
const root = @import("root");
const options = root.cathode_run_options;

const std = @import("std");
const assert = std.debug.assert;
const errno = std.posix.errno;
const log = std.log.scoped(.platform);
const Allocator = std.mem.Allocator;

const core = @import("core");
const game = core.game;
const static = core.static;
const unit = core.unit;
const Txt = core.Txt;

const Audio = @import("Terminal/Audio.zig");

audio: Audio,
txt: Txt,
stdout_buf: [*]u8,
win_size: game.Point.U,
last_frame: u64 = 0,
impl: Impl = .{},
attr: *const fn (ca: game.CellAttr) []const u8,

const stdout_buf_len = unit.MB(1);
const spinloop_max = unit.ms(6).toNs();

const Platform = @This();
const Impl = if (builtin.os.tag == .windows)
    @import("Terminal/Windows.zig")
else
    @import("Terminal/Posix.zig");

const RenderIndexer = struct {
    idx: usize = 0,
    pos: game.Point.U = .{},

    fn add(i: *@This(), dx: usize, w: usize) void {
        i.idx += dx;
        i.pos.x += @intCast(dx);
        while (i.pos.x >= w) i.nl(w);
    }

    fn nl(i: *@This(), w: usize) void {
        i.pos.x -= @intCast(w);
        i.pos.y += 1;
    }

    fn check(i: @This(), len: usize) bool {
        return i.idx < len;
    }
};

pub fn init(gpa: Allocator) !@This() {
    var audio = try Audio.init(gpa);
    errdefer audio.deinit(gpa);
    var txt = try Txt.init(gpa, .MB(1));
    errdefer txt.deinit(gpa);
    const stdout_buf = try stdout_buf_len.alloc(gpa);
    errdefer gpa.free(stdout_buf);
    const supports_24bit = try Impl.supports24BitColor(gpa);
    log.info("24bit mode: {}", .{supports_24bit});
    return .{
        .audio = audio,
        .txt = txt,
        .stdout_buf = stdout_buf.ptr,
        .win_size = try Impl.getWinSize(),
        .attr = if (supports_24bit) static.ansi.attr24Bit else static.ansi.attr,
    };
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.audio.deinit(gpa);
    self.txt.deinit(gpa);
    stdout_buf_len.free(gpa, self.stdout_buf);
    self.* = undefined;
}

pub fn setup(self: *@This()) !void {
    try self.impl.setup(self.stdout_buf[0..stdout_buf_len.v]);
    self.last_frame = try self.impl.getNow();
}

pub fn teardown(self: *@This()) !void {
    try self.impl.teardown();
}

pub fn reset(self: *@This(), session: *game.Session) !void {
    _ = self;
    if (options.random_seed orelse !options.debug) {
        try Impl.randomBytes(std.mem.asBytes(&session.seed));
    } else {
        session.seed = 0;
    }
    log.info("reset seed: {x:016}", .{session.seed});
}

pub fn playSound(self: *@This(), path: [:0]const u8) !void {
    log.debug("playing sample: {s}", .{path});
    try self.audio.playSound(path);
}

pub fn getInput(self: *@This(), buf: []core.InputResult) !bool {
    return try self.impl.readInput(buf);
}

pub fn renderFull(self: *@This(), frame: *core.Frame) !void {
    assert(frame.syms.len == self.win_size.area());
    assert(frame.syms.len == frame.attrs.len);
    assert(frame.syms.len == self.win_size.area());

    var i: RenderIndexer = .{};
    while (i.check(frame.syms.len)) {
        const start = i.idx;
        const end = for (start..frame.syms.len) |n| {
            if (frame.attrs[n] != frame.attrs[start]) break n;
        } else frame.syms.len;
        try self.txt.write(self.attr(frame.attrs[start]));
        try self.txt.writeSyms(frame.syms[start..end]);
        i.add(end - i.idx, self.win_size.x);
    }
    try self.txt.write(static.ansi.sync_end);
    try self.write(self.txt.commit());
}

pub fn renderDelta(self: *const @This(), prev_frame: *core.Frame, frame: *core.Frame) !void {
    assert(frame.text.len == self.win_size.area());
    assert(frame.text.len == frame.attrs.len);
    assert(frame.text.len == prev_frame.text.len);
    assert(frame.text.len == prev_frame.attrs.len);
    assert(frame.text.len == self.win_size.area());

    const Indexer = struct {
        idx: usize = 0,
        pos: game.Point.U = .{},

        fn add(i: *@This(), dx: u32) void {
            i.idx += dx;
            i.pos.x += dx;
            while (i.pos.x >= self.win_size.x) i.nl();
        }

        fn nl(i: *@This()) void {
            i.pos.x -= self.win_size.x;
            i.pos.y += 1;
        }

        fn check(i: @This()) bool {
            return i.idx < frame.text.len;
        }
    };

    try self.txt.write(static.ansi.sync_start);
    var i: Indexer = .{};
    while (i.check()) {
        const start = for (i.idx..frame.text.len) |n| {
            if ((frame.text[n] != prev_frame.text[n]) |
                (frame.attrs[n] != prev_frame.attrs[n])) break n;
        } else break;
        const skip = start - i.idx;
        if (skip > 0) try self.txt.print(static.ansi.cur_pos, .{ i.pos.y + 1, i.pos.x + 1 });
        const end = for (start..frame.text.len) |n| {
            if (frame.attrs[n] != frame.attrs[start]) break n;
        } else frame.text.len;
        try self.txt.write(static.ansi.attr(frame.attrs[start]));
        try self.txt.writeSyms(frame.text[start..end]);
        i.add(end - i.idx);
    }
    try self.txt.write(static.ansi.sync_end);
    try self.write(self.txt.commit());
}

pub fn write(self: *const @This(), buf: []const u8) !void {
    try self.impl.write(buf);
}

pub fn sleep(self: *@This(), delay: u64) !void {
    try self.sleepNs(unit.us(delay).toNs());
}

pub fn getNow(self: *@This()) !u64 {
    return self.impl.getNow();
}

fn sleepNs(self: *@This(), delay: u64) !void {
    const frame_end = try self.impl.getNow();
    if (frame_end - self.last_frame < delay) {
        const to_wait = delay - (frame_end - self.last_frame);
        // TODO: variable SPINLOOP_MAX if delta keeps overflowing?
        if (to_wait > spinloop_max) try Impl.sleepNs(to_wait - spinloop_max);
        var now = try self.impl.getNow();
        const spinloop_start = now;
        while (now - self.last_frame < delay) {
            std.atomic.spinLoopHint();
            now = try self.impl.getNow();
        }
        log.debug("sleep: {}, spinloop: {}, total: {}, target: {}, delta: {}", .{
            to_wait -| spinloop_max,
            now - spinloop_start,
            now - self.last_frame,
            delay,
            (now - self.last_frame) - delay,
        });
        self.last_frame = now;
    } else self.last_frame += delay;
}
