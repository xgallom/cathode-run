const builtin = @import("builtin");
const root = @import("root");
const options = root.cathode_run_options;

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.platform);
const windows = std.os.windows;
const Allocator = std.mem.Allocator;

const core = @import("core");
const game = core.game;
const static = core.static;
const unit = core.unit;
const Txt = core.Txt;

output_mode: u32 = undefined,
input_mode: u32 = undefined,
output: windows.HANDLE = undefined,
input: windows.HANDLE = undefined,
pc_freq: u64 = 0,
event_buf: [options.input_buf_length - 1]INPUT_RECORD = undefined,

const spinloop_max = unit.ms(6).toNs();

const KEY_EVENT: u16 = 0x0010;

const ENABLE_PROCESSED_OUTPUT: u32 = 0x0001;
const ENABLE_WRAP_AT_EOL_OUTPUT: u32 = 0x0002;
const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
const DISABLE_NEWLINE_AUTO_RETURN: u32 = 0x0008;
const ENABLE_LVB_GRID_WORLDWIDE: u32 = 0x0010;

const ENABLE_ECHO_INPUT: u32 = 0x0004;
const ENABLE_INSERT_MODE: u32 = 0x0020;
const ENABLE_LINE_INPUT: u32 = 0x0002;
const ENABLE_MOUSE_INPUT: u32 = 0x0010;
const ENABLE_PROCESSED_INPUT: u32 = 0x0001;
const ENABLE_QUICK_EDIT_MODE: u32 = 0x0040;
const ENABLE_WINDOW_INPUT: u32 = 0x0008;
const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;

const CONSOLE_READ_NOWAIT: windows.USHORT = 0x0002;

const BCRYPT_RNG_USE_ENTROPY_IN_BUFFER = 0x00000001;
const BCRYPT_USE_SYSTEM_PREFERRED_RNG = 0x00000002;

const INPUT_RECORD = extern struct {
    EventType: windows.WORD,
    Event: extern union {
        KeyEvent: KEY_EVENT_RECORD,
    },
};

const KEY_EVENT_RECORD = extern struct {
    bKeyDown: windows.BOOL,
    wRepeatCount: windows.WORD,
    wVirtualKeyCode: windows.WORD,
    wVirtualScanCode: windows.WORD,
    uChar: extern union {
        UnicodeChar: windows.WCHAR,
        AsciiChar: windows.CHAR,
    },
    dwControlKeyState: windows.DWORD,
};

extern "ntdll" fn NtDelayExecution(
    Alertable: windows.BOOLEAN,
    DelayInterval: *const windows.LARGE_INTEGER,
) callconv(.winapi) windows.NTSTATUS;

extern "kernel32" fn GetNumberOfConsoleInputEvents(
    hConsoleInput: windows.HANDLE,
    lpcNumberOfEvents: *windows.DWORD,
) callconv(.winapi) windows.BOOL;

extern "kernel32" fn ReadConsoleInputW(
    hConsoleInput: windows.HANDLE,
    lpBuffer: [*]INPUT_RECORD,
    nLength: windows.DWORD,
    lpNumberOfEventsRead: *windows.DWORD,
) callconv(.winapi) windows.BOOL;

extern "bcrypt" fn BCryptGenRandom(
    hAlgorithm: ?windows.PVOID,
    pbBuffer: [*]windows.UCHAR,
    cbBuffer: windows.ULONG,
    dwFlags: windows.ULONG,
) callconv(.winapi) windows.NTSTATUS;

pub fn setup(self: *@This(), stdout_buf: []u8) !void {
    _ = stdout_buf;
    try self.initPerformanceCounter();
    try self.enableAnsiSequences();
    try self.write(static.ansi.alt_scr_buf ++ static.ansi.cls);
    try self.enableRawMode();
}

pub fn teardown(self: *@This()) !void {
    try self.disableRawMode();
    try self.write(static.ansi.cls ++ static.ansi.alt_scr_buf_end);
    try self.disableAnsiSequences();
}

pub fn getWinSize() !game.Point.U {
    if (windows.kernel32.GetStdHandle(windows.STD_OUTPUT_HANDLE)) |output| {
        var info: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (windows.kernel32.GetConsoleScreenBufferInfo(output, &info) == windows.FALSE) {
            log.err("failed obtaining console screen buffer info", .{});
            return error.SetConsoleScreenBufferInfoFailed;
        }
        return .{
            .x = @intCast(info.srWindow.Right - info.srWindow.Left + 1),
            .y = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1),
        };
    } else {
        log.err("failed obtaining output handle", .{});
        return error.GetStdHandleFailed;
    }
}

pub fn getNow(self: *@This()) !u64 {
    const ticks: u128 = windows.QueryPerformanceCounter();
    return @intCast(ticks * std.time.ns_per_s / self.pc_freq);
}

pub fn sleepNs(ns: u64) !void {
    const di: windows.LARGE_INTEGER = -@as(i64, @intCast(ns / 100));
    const status = NtDelayExecution(windows.FALSE, &di);
    if (@intFromEnum(status) & 0x80000000 != 0) {
        log.err("delay execution failed: {t}", .{status});
        return error.NtDelayExecutionFailed;
    }
}

pub fn randomBytes(buf: []u8) void {
    const status = BCryptGenRandom(null, buf.ptr, @intCast(buf.len), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    if (status != .SUCCESS) {
        std.process.fatal("random bytes failed: {t}", .{status});
        return error.BCryptGenRandomFailed;
    }
}

pub fn readInput(self: *@This(), buf: []core.InputResult) !bool {
    var max_len: windows.DWORD = undefined;
    if (GetNumberOfConsoleInputEvents(self.input, &max_len) == windows.FALSE) {
        log.err("failed obtaining number of input events", .{});
        return error.GetNumberOfConsoleInputEventsFailed;
    }
    if (max_len == 0) {
        buf[0] = .none;
        return false;
    }
    var len: windows.DWORD = undefined;
    if (ReadConsoleInputW(self.input, &self.event_buf, self.event_buf.len, &len) == windows.FALSE) {
        log.err("failed obtaining input events", .{});
        return error.ReadConsoleInputFailed;
    }
    var n: usize = 0;
    for (self.event_buf[0..len]) |*event| {
        if (event.EventType == KEY_EVENT) {
            const ker: KEY_EVENT_RECORD = event.Event.KeyEvent;
            const virtual_key = ker.wVirtualKeyCode;
            if (virtual_key >= 256) continue;
            if (ker.bKeyDown != windows.FALSE) {
                buf[n] = .down(@intCast(virtual_key));
                n += 1;
            } else {
                buf[n] = .up(@intCast(virtual_key));
                n += 1;
            }
        }
    }
    assert(n < buf.len);
    buf[n] = .none;
    return len >= max_len;
}

pub fn write(self: *const @This(), buf: []const u8) !void {
    if (buf.len == 0) return;
    if (try windows.WriteFile(self.output, buf, null) != buf.len) {
        return error.WriteFailed;
    }
}

fn initPerformanceCounter(self: *@This()) !void {
    self.pc_freq = windows.QueryPerformanceFrequency();
}

fn enableAnsiSequences(self: *@This()) !void {
    if (windows.kernel32.GetStdHandle(windows.STD_OUTPUT_HANDLE)) |output| {
        self.output = output;
        if (windows.kernel32.GetConsoleMode(output, &self.output_mode) == windows.FALSE) {
            log.err("failed obtaining console output mode", .{});
            return error.GetConsoleModeFailed;
        }
        if (windows.kernel32.SetConsoleMode(output, self.output_mode |
            ENABLE_VIRTUAL_TERMINAL_PROCESSING |
            DISABLE_NEWLINE_AUTO_RETURN) == windows.FALSE)
        {
            log.err("failed setting console output mode", .{});
            return error.SetConsoleModeFailed;
        }
    } else {
        log.err("failed obtaining output handle", .{});
        return error.GetStdHandleFailed;
    }
}

fn disableAnsiSequences(self: *@This()) !void {
    if (windows.kernel32.SetConsoleMode(self.output, self.output_mode) == windows.FALSE) {
        log.err("failed setting console output mode", .{});
        return error.SetConsoleModeFailed;
    }
}

fn enableRawMode(self: *@This()) !void {
    if (windows.kernel32.GetStdHandle(windows.STD_INPUT_HANDLE)) |input| {
        self.input = input;
        if (windows.kernel32.GetConsoleMode(input, &self.input_mode) == windows.FALSE) {
            log.err("failed obtaining console input mode", .{});
            return error.GetConsoleModeFailed;
        }
        if (windows.kernel32.SetConsoleMode(input, self.input_mode &
            ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT) |
            (ENABLE_WINDOW_INPUT)) == windows.FALSE)
        {
            log.err("failed setting console input mode", .{});
            return error.SetConsoleModeFailed;
        }
    } else {
        log.err("failed obtaining input handle", .{});
        return error.GetStdHandleFailed;
    }
    try self.write(static.ansi.cur_hide);
}

fn disableRawMode(self: *const @This()) !void {
    if (windows.kernel32.SetConsoleMode(self.input, self.input_mode) == windows.FALSE) {
        log.err("failed setting console input mode", .{});
        return error.SetConsoleModeFailed;
    }
    try self.write(static.ansi.cur_show);
}
