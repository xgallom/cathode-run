const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.txt);
const Allocator = std.mem.Allocator;

const cp437 = @import("cp437.zig");
const unit = @import("unit.zig");

head: [*]u8,
tail: [*]u8,
capacity: unit.Bytes,

pub fn init(gpa: Allocator, capacity: unit.Bytes) !@This() {
    const buf = try capacity.alloc(gpa);
    return .{ .head = buf.ptr, .tail = buf.ptr, .capacity = capacity };
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.capacity.free(gpa, self.tail);
    self.* = undefined;
}

pub fn commit(self: *@This()) []const u8 {
    defer self.head = self.tail;
    log.debug("commit {}", .{self.len()});
    return self.tail[0..self.len()];
}

pub fn print(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
    const result = std.fmt.bufPrint(self.head[0..self.available()], fmt, args) catch |err| {
        log.err(
            "print: buffer overflow @{}: {}",
            .{ self.len(), self.available() },
        );
        return err;
    };
    self.head += result.len;
    log.debug("print {}", .{result.len});
}

pub fn writeSyms(self: *@This(), syms: []const u8) !void {
    const max_total = syms.len * cp437.str_len_max;
    if (self.available() < max_total) {
        log.err(
            "write syms: buffer overflow @{}: {}",
            .{ self.len(), max_total },
        );
        return error.BufferOverflow;
    }
    var head = self.head;
    for (syms) |sym| {
        const src = cp437.resolve(sym);
        @memcpy(head[0..src.len], src);
        head += src.len;
    }
    log.debug("write syms {}", .{head - self.head});
    self.head = head;
}

pub fn writeSym(self: *@This(), sym: u8) !void {
    const src = cp437.resolve(sym);
    if (self.available() < src.len) {
        log.err(
            "write sym: buffer overflow @{}: {}",
            .{ self.len(), src.len },
        );
        return error.BufferOverflow;
    }
    @memcpy(self.head[0..src.len], src);
    self.head += src.len;
    log.debug("write sym {}", .{src.len});
}

pub fn write(self: *@This(), src: []const u8) !void {
    if (self.available() < src.len) {
        log.err(
            "write: buffer overflow @{}: {}",
            .{ self.len(), src.len },
        );
        return error.BufferOverflow;
    }
    @memcpy(self.head[0..src.len], src);
    self.head += src.len;
    log.debug("write {}", .{src.len});
}

pub fn fill(self: *@This(), val: u8, count: usize) !void {
    if (self.available() < count) {
        log.err("fill: buffer overflow @{}: {}", .{ self.len(), count });
        return error.BufferOverflow;
    }
    @memset(self.head[0..count], val);
    self.head += count;
    log.debug("fill {}", .{count});
}

fn available(self: @This()) usize {
    return self.capacity.available(self.len());
}

fn len(self: @This()) usize {
    return self.head - self.tail;
}
