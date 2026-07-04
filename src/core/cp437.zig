const std = @import("std");
const log = std.log.scoped(.cp437);
const assert = std.debug.assert;

pub const str_len_max = blk: {
    var acc = 0;
    for (raw_utf8) |str| acc = @max(acc, str.len);
    break :blk acc;
};

pub fn resolve(sym: u8) []const u8 {
    const result = index[sym].resolve();
    log.debug("resolve {x:02} {c} -> {f}", .{ sym, sym, index[sym] });
    return result;
}

pub fn resolveUnivode(sym: u8) u32 {
    const result = raw_unicode[sym];
    log.debug("resolve {x:02} {c} -> 0x{x:04}", .{ sym, sym, result });
    return result;
}

const Index = packed struct {
    len: u2,
    offset: u14,

    comptime {
        assert(std.math.maxInt(u2) >= str_len_max);
        assert(std.math.maxInt(u14) >= data_len);
    }

    fn resolve(self: @This()) []const u8 {
        return data[self.offset .. self.offset + self.len];
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print(
            "@{x:04}[{}] {x}",
            .{ self.offset, self.len, self.resolve() },
        );
    }
};

const sym_count = std.math.maxInt(u8) + 1;
const index: [sym_count]Index = blk: {
    var result: [sym_count]Index = undefined;
    var offset = 0;
    for (raw_utf8, 0..) |str, n| {
        result[n] = .{
            .len = @intCast(str.len),
            .offset = @intCast(offset),
        };
        offset += str.len;
    }
    break :blk result;
};

const data_len = blk: {
    var acc = 0;
    for (raw_utf8) |str| acc += str.len;
    break :blk acc;
};

const data: [data_len]u8 = blk: {
    var result: [data_len]u8 = undefined;
    var n = 0;
    for (raw_utf8) |str| {
        for (str) |c| {
            result[n] = c;
            n += 1;
        }
    }
    assert(n == data_len);
    break :blk result;
};

// if we ever want to replace '\n': "\x0A" -> "\xE2\x97\x99"
const raw_utf8: [sym_count][]const u8 = .{
    "\x00",         "\xE2\x98\xBA", "\xE2\x98\xBB", "\xE2\x99\xA5",
    "\xE2\x99\xA6", "\xE2\x99\xA3", "\xE2\x99\xA0", "\xE2\x80\xA2",
    "\xE2\x97\x98", "\xE2\x97\x8B", "\x0A",         "\xE2\x99\x82",
    "\xE2\x99\x80", "\xE2\x99\xAA", "\xE2\x99\xAB", "\xE2\x98\xBC",
    "\xE2\x96\xBA", "\xE2\x97\x84", "\xE2\x86\x95", "\xE2\x80\xBC",
    "\xC2\xB6",     "\xC2\xA7",     "\xE2\x96\xAC", "\xE2\x86\xA8",
    "\xE2\x86\x91", "\xE2\x86\x93", "\xE2\x86\x92", "\xE2\x86\x90",
    "\xE2\x88\x9F", "\xE2\x86\x94", "\xE2\x96\xB2", "\xE2\x96\xBC",
    "\x20",         "\x21",         "\x22",         "\x23",
    "\x24",         "\x25",         "\x26",         "\x27",
    "\x28",         "\x29",         "\x2A",         "\x2B",
    "\x2C",         "\x2D",         "\x2E",         "\x2F",
    "\x30",         "\x31",         "\x32",         "\x33",
    "\x34",         "\x35",         "\x36",         "\x37",
    "\x38",         "\x39",         "\x3A",         "\x3B",
    "\x3C",         "\x3D",         "\x3E",         "\x3F",
    "\x40",         "\x41",         "\x42",         "\x43",
    "\x44",         "\x45",         "\x46",         "\x47",
    "\x48",         "\x49",         "\x4A",         "\x4B",
    "\x4C",         "\x4D",         "\x4E",         "\x4F",
    "\x50",         "\x51",         "\x52",         "\x53",
    "\x54",         "\x55",         "\x56",         "\x57",
    "\x58",         "\x59",         "\x5A",         "\x5B",
    "\x5C",         "\x5D",         "\x5E",         "\x5F",
    "\x60",         "\x61",         "\x62",         "\x63",
    "\x64",         "\x65",         "\x66",         "\x67",
    "\x68",         "\x69",         "\x6A",         "\x6B",
    "\x6C",         "\x6D",         "\x6E",         "\x6F",
    "\x70",         "\x71",         "\x72",         "\x73",
    "\x74",         "\x75",         "\x76",         "\x77",
    "\x78",         "\x79",         "\x7A",         "\x7B",
    "\x7C",         "\x7D",         "\x7E",         "\x7F",
    "\xC3\x87",     "\xC3\xBC",     "\xC3\xA9",     "\xC3\xA2",
    "\xC3\xA4",     "\xC3\xA0",     "\xC3\xA5",     "\xC3\xA7",
    "\xC3\xAA",     "\xC3\xAB",     "\xC3\xA8",     "\xC3\xAF",
    "\xC3\xAE",     "\xC3\xAC",     "\xC3\x84",     "\xC3\x85",
    "\xC3\x89",     "\xC3\xA6",     "\xC3\x86",     "\xC3\xB4",
    "\xC3\xB6",     "\xC3\xB2",     "\xC3\xBB",     "\xC3\xB9",
    "\xC3\xBF",     "\xC3\x96",     "\xC3\x9C",     "\xC2\xA2",
    "\xC2\xA3",     "\xC2\xA5",     "\xE2\x82\xA7", "\xC6\x92",
    "\xC3\xA1",     "\xC3\xAD",     "\xC3\xB3",     "\xC3\xBA",
    "\xC3\xB1",     "\xC3\x91",     "\xC2\xAA",     "\xC2\xBA",
    "\xC2\xBF",     "\xE2\x8C\x90", "\xC2\xAC",     "\xC2\xBD",
    "\xC2\xBC",     "\xC2\xA1",     "\xC2\xAB",     "\xC2\xBB",
    "\xE2\x96\x91", "\xE2\x96\x92", "\xE2\x96\x93", "\xE2\x94\x82",
    "\xE2\x94\xA4", "\xE2\x95\xA1", "\xE2\x95\xA2", "\xE2\x95\x96",
    "\xE2\x95\x95", "\xE2\x95\xA3", "\xE2\x95\x91", "\xE2\x95\x97",
    "\xE2\x95\x9D", "\xE2\x95\x9C", "\xE2\x95\x9B", "\xE2\x94\x90",
    "\xE2\x94\x94", "\xE2\x94\xB4", "\xE2\x94\xAC", "\xE2\x94\x9C",
    "\xE2\x94\x80", "\xE2\x94\xBC", "\xE2\x95\x9E", "\xE2\x95\x9F",
    "\xE2\x95\x9A", "\xE2\x95\x94", "\xE2\x95\xA9", "\xE2\x95\xA6",
    "\xE2\x95\xA0", "\xE2\x95\x90", "\xE2\x95\xAC", "\xE2\x95\xA7",
    "\xE2\x95\xA8", "\xE2\x95\xA4", "\xE2\x95\xA5", "\xE2\x95\x99",
    "\xE2\x95\x98", "\xE2\x95\x92", "\xE2\x95\x93", "\xE2\x95\xAB",
    "\xE2\x95\xAA", "\xE2\x94\x98", "\xE2\x94\x8C", "\xE2\x96\x88",
    "\xE2\x96\x84", "\xE2\x96\x8C", "\xE2\x96\x90", "\xE2\x96\x80",
    "\xCE\xB1",     "\xC3\x9F",     "\xCE\x93",     "\xCF\x80",
    "\xCE\xA3",     "\xCF\x83",     "\xC2\xB5",     "\xCF\x84",
    "\xCE\xA6",     "\xCE\x98",     "\xCE\xA9",     "\xCE\xB4",
    "\xE2\x88\x9E", "\xCF\x86",     "\xCE\xB5",     "\xE2\x88\xA9",
    "\xE2\x89\xA1", "\xC2\xB1",     "\xE2\x89\xA5", "\xE2\x89\xA4",
    "\xE2\x8C\xA0", "\xE2\x8C\xA1", "\xC3\xB7",     "\xE2\x89\x88",
    "\xC2\xB0",     "\xE2\x88\x99", "\xC2\xB7",     "\xE2\x88\x9A",
    "\xE2\x81\xBF", "\xC2\xB2",     "\xE2\x96\xA0", "\xC2\xA0",
};

const raw_unicode: [256]u32 = .{
    0,      0x263A, 0x263B, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022,
    0x25D8, 0x25CB, 0x25D9, 0x2642, 0x2640, 0x266A, 0x266B, 0x263C,
    0x25BA, 0x25C4, 0x2195, 0x203C, 0x00B6, 0x00A7, 0x25AC, 0x21A8,
    0x2191, 0x2193, 0x2192, 0x2190, 0x221F, 0x2194, 0x25B2, 0x25BC,
    ' ',    '!',    '"',    '#',    '$',    '%',    '&',    '\'',
    '(',    ')',    '*',    '+',    ',',    '-',    '.',    '/',
    '0',    '1',    '2',    '3',    '4',    '5',    '6',    '7',
    '8',    '9',    ':',    ';',    '<',    '=',    '>',    '?',
    '@',    'A',    'B',    'C',    'D',    'E',    'F',    'G',
    'H',    'I',    'J',    'K',    'L',    'M',    'N',    'O',
    'P',    'Q',    'R',    'S',    'T',    'U',    'V',    'W',
    'X',    'Y',    'Z',    '[',    '\\',   ']',    '^',    '_',
    '`',    'a',    'b',    'c',    'd',    'e',    'f',    'g',
    'h',    'i',    'j',    'k',    'l',    'm',    'n',    'o',
    'p',    'q',    'r',    's',    't',    'u',    'v',    'w',
    'x',    'y',    'z',    '{',    '|',    '}',    '~',    0x2302,
    0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7,
    0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
    0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9,
    0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
    0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA,
    0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
    0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
    0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,
    0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,
    0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
    0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4,
    0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
    0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248,
    0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0,
};
