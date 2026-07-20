const builtin = @import("builtin");
const root = @import("root");
const options = root.cathode_run_options;

const std = @import("std");
const assert = std.debug.assert;
const errno = std.posix.errno;
const log = std.log.scoped(.platform);
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/random.h");
    @cInclude("sys/select.h");
    @cInclude("termios.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});

const core = @import("core");
const game = core.game;
const static = core.static;
const unit = core.unit;
const Txt = core.Txt;

const ReadKbdRaw = @import("ReadKbdRaw.zig");

termios: c.termios = undefined,
read: ReadKbdRaw = .{},

pub fn setup(self: *@This(), stdout_buf: []u8) !void {
    try self.setVBuf(stdout_buf);
    try self.write(static.ansi.alt_scr_buf ++ static.ansi.cls);
    try self.enableRawMode();
}

pub fn teardown(self: *@This()) !void {
    try self.disableRawMode();
    try self.write(static.ansi.cls ++ static.ansi.alt_scr_buf_end);
}

pub fn getWinSize() !game.Point.U {
    var w: c.winsize = undefined;
    switch (errno(c.ioctl(c.STDIN_FILENO, c.TIOCGWINSZ, &w))) {
        .SUCCESS => {},
        else => |err| {
            log.err("ioctl failed: {t}", .{err});
            return error.WinSizeFailed;
        },
    }
    return .{ .x = w.ws_col, .y = w.ws_row };
}

pub fn getNow(self: *@This()) !u64 {
    _ = self;
    var ts: std.c.timespec = undefined;
    switch (errno(std.c.clock_gettime(std.c.clockid_t.MONOTONIC, &ts))) {
        .SUCCESS => {},
        else => |err| {
            log.err("clock gettime failed: {t}", .{err});
            return error.ClockGetTimeFailed;
        },
    }
    return unit.s(@intCast(ts.sec)).toNs() + @as(u64, @intCast(ts.nsec));
}

pub fn sleepNs(ns: u64) !void {
    var ts: std.c.timespec = .{ .sec = 0, .nsec = @intCast(ns) };
    switch (errno(std.c.nanosleep(&ts, null))) {
        .SUCCESS => {},
        else => |err| {
            log.err("nanosleep failed: {t}", .{err});
            return error.NanoSleepFailed;
        },
    }
}

pub fn randomBytes(buf: []u8) !void {
    if (@hasDecl(c, "arc4random_buf")) {
        c.arc4random_buf(buf.ptr, buf.len);
    } else if (@hasDecl(c, "getrandom")) {
        switch (errno(c.getrandom(buf.ptr, buf.len, 0))) {
            .SUCCESS => {},
            else => |err| {
                log.err("getrandom failed: {t}", .{err});
                return error.GetrandomFailed;
            },
        }
    } else @compileError("Missing random number generator");
}

pub fn readInput(self: *@This(), buf: []core.InputResult) !bool {
    for (0..buf.len) |n| {
        buf[n] = self.read.parse(takeByte);
        if ((buf[n].event == .none) | (buf[n].event == .err)) return true;
    }
    return false;
}

pub fn write(self: *const @This(), buf: []const u8) !void {
    _ = self;
    if (buf.len == 0) return;
    if (c.fwrite(buf.ptr, buf.len, 1, stdout()) != 1) {
        return error.WriteFailed;
    }
    if (c.fflush(stdout()) != 0) return error.FlushFailed;
}

pub fn supports24BitColor(gpa: Allocator) !bool {
    const colorterm = try std.process.getEnvVarOwned(gpa, "COLORTERM");
    defer gpa.free(colorterm);
    for (colorterm) |*ch| ch.* = std.ascii.toLower(ch.*);
    if (std.mem.indexOf(u8, colorterm, "24bit") != null or
        std.mem.indexOf(u8, colorterm, "truecolor") != null) return true;
    const term = try std.process.getEnvVarOwned(gpa, "TERM");
    defer gpa.free(term);
    for (term) |*ch| ch.* = std.ascii.toLower(ch.*);
    if (std.mem.indexOf(u8, term, "24bit") != null or
        std.mem.indexOf(u8, term, "truecolor") != null) return true;
    return false;
}

fn setVBuf(self: *const @This(), buf: []u8) !void {
    _ = self;
    switch (errno(c.setvbuf(stdout(), buf.ptr, c._IOFBF, buf.len))) {
        .SUCCESS => {},
        else => |err| {
            log.err("setvbuf failed: {t}", .{err});
            return error.SetvbufFailed;
        },
    }
}

fn takeByte() ?u8 {
    if (!kbhit()) return null;
    const result = getch();
    log.debug("getch: {x:02} {c}", .{ result, result });
    if (result != 0) {
        return result;
    } else {
        log.warn("read returned 0", .{});
        return null;
    }
}

fn kbhit() bool {
    var tv: c.timeval = .{ .tv_sec = 0, .tv_usec = 0 };
    var fds: c.fd_set = .{};
    FD.fdZero(&fds);
    FD.fdSet(c.STDIN_FILENO, &fds);
    const result = c.select(1, &fds, null, null, &tv);
    switch (errno(result)) {
        .SUCCESS => return result > 0,
        else => |err| {
            log.err("select failed: {t}", .{err});
            return false;
        },
    }
}

fn getch() u8 {
    var result: u8 = undefined;
    if (c.read(c.STDIN_FILENO, &result, 1) > 0) {
        return result;
    } else return 0;
}

fn enableRawMode(self: *@This()) !void {
    switch (errno(c.tcgetattr(c.STDIN_FILENO, &self.termios))) {
        .SUCCESS => {},
        else => |err| {
            log.err("tcgetattr failed: {t}", .{err});
            return error.TCGetAttrFailed;
        },
    }
    errdefer self.disableRawMode() catch |err| log.err("disabling raw mode failed: {t}", .{err});
    var raw = self.termios;
    raw.c_lflag &= ~@as(c.tcflag_t, c.ECHO | c.ICANON);
    raw.c_cc[c.VMIN] = 0;
    raw.c_cc[c.VTIME] = 0;
    switch (errno(c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw))) {
        .SUCCESS => {},
        else => |err| {
            log.err("tcsetattr failed: {t}", .{err});
            return error.TCSetAttrFailed;
        },
    }

    try self.write(static.ansi.query_pe ++ static.ansi.query_da);
    var input_buf: [17]core.InputResult = undefined;
    var is_pe = false;
    var is_da = false;
    for (0..100) |_| {
        _ = try self.readInput(&input_buf);
        for (&input_buf) |input| switch (input.event) {
            .none => break,
            .err => return error.InputFailed,
            .query => switch (input.queryType()) {
                .pe => is_pe = true,
                .da => is_da = true,
            },
            else => {},
        };
        if (is_da) {
            if (is_pe) {
                log.debug("Querying keyboard mode sucessful", .{});
                try self.write(static.ansi.cur_hide ++ static.ansi.kbd_raw);
                return;
            } else {
                log.err("Application requires Kitty Keyboard Protocol", .{});
                return error.KeyboardProtocolNotSupported;
            }
        }
        try sleepNs(static.delay.step);
    }
    log.err("Failed querying device attributes", .{});
    return error.QueryingDeviceAttributesFailed;
}

fn disableRawMode(self: *const @This()) !void {
    switch (errno(c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &self.termios))) {
        .SUCCESS => {},
        else => |err| {
            log.err("tcsetattr failed: {t}", .{err});
            return error.TCSetAttrFailed;
        },
    }
    try self.write(static.ansi.cur_show ++ static.ansi.kbd_raw_end);
}

fn stdout() *c.FILE {
    if (@typeInfo(@TypeOf(c.stdout)) == .@"fn") {
        return c.stdout();
    } else return c.stdout.?;
}

// WARN: This seems awfully hacky, check when porting
const FD = struct {
    fn fdZero(set: *c.fd_set) void {
        set.fds_bits = @splat(0);
    }

    fn fdSet(fd: c_int, set: *c.fd_set) void {
        const ufd: usize = @intCast(fd);
        const index = ufd / 32;
        const bit: u5 = @intCast(ufd % 32);
        set.fds_bits[index] |= @intCast((@as(u32, 1) << bit));
    }
};
