const std = @import("std");
const log = std.log.scoped(.read);

const core = @import("core");

state: State = .begin,
result: core.InputResult = .none,

pub const State = enum {
    begin,
    esc,
    bracket,
    question_mark,
    semicolon,
    colon,
    end,
};

pub fn parse(self: *@This(), comptime takeByte: fn () ?u8) core.InputResult {
    loop: switch (self.state) {
        .begin => {
            log.debug("begin", .{});
            const c = takeByte() orelse return .none;
            self.result = .none;
            if (c == 0x1b) {
                self.state = .esc;
                continue :loop .esc;
            } else {
                log.err("begin: expected esc {x:02}", .{c});
                return .err;
            }
        },
        .esc => {
            log.debug("esc", .{});
            const c = takeByte() orelse return .none;
            if (c == '[') {
                self.state = .bracket;
                continue :loop .bracket;
            } else {
                log.err("esc: expected [ {x:02}", .{c});
                return .err;
            }
        },
        .bracket => {
            log.debug("bracket", .{});
            const c = takeByte() orelse return .none;
            switch (c) {
                '0'...'9' => {
                    self.result.keycode *= 10;
                    self.result.keycode += c - '0';
                    continue :loop .bracket;
                },
                '?' => {
                    self.state = .question_mark;
                    continue :loop .question_mark;
                },
                ';' => {
                    self.state = .semicolon;
                    continue :loop .semicolon;
                },
                ':' => {
                    self.state = .colon;
                    continue :loop .colon;
                },
                'u' => {
                    self.state = .begin;
                    return .down(self.result.keycode);
                },
                else => {
                    log.err("bracket: invalid character {x:02}", .{c});
                    return .err;
                },
            }
        },
        .question_mark => {
            log.debug("question_mark", .{});
            const c = takeByte() orelse return .none;
            switch (c) {
                '0'...'9', ';' => continue :loop .question_mark,
                'u' => {
                    self.state = .begin;
                    return .query(.pe);
                },
                'c' => {
                    self.state = .begin;
                    return .query(.da);
                },
                else => {
                    log.err("question_mark: invalid character {x:02}", .{c});
                    return .err;
                },
            }
        },
        .semicolon => {
            log.debug("semicolon", .{});
            const c = takeByte() orelse return .none;
            switch (c) {
                '0'...'9', ';' => continue :loop .semicolon,
                ':' => {
                    self.state = .colon;
                    continue :loop .colon;
                },
                'u' => {
                    self.state = .begin;
                    return .down(self.result.keycode);
                },
                else => {
                    log.err("semicolon: invalid character {x:02}", .{c});
                    return .err;
                },
            }
        },
        .colon => {
            log.debug("colon", .{});
            const c = takeByte() orelse return .none;
            switch (c) {
                '1', '2' => {
                    self.result.event = .down;
                    self.state = .end;
                    continue :loop .end;
                },
                '3' => {
                    self.result.event = .up;
                    self.state = .end;
                    continue :loop .end;
                },
                else => {
                    log.err("colon: invalid character {x:02}", .{c});
                    return .err;
                },
            }
        },
        .end => {
            log.debug("end", .{});
            const c = takeByte() orelse return .none;
            switch (c) {
                'u' => {
                    self.state = .begin;
                    return self.result;
                },
                else => {
                    log.err("end: expected u {x:02}", .{c});
                    return .err;
                },
            }
        },
    }
}
