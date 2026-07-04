const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.scratch);
const Allocator = std.mem.Allocator;

const unit = @import("unit.zig");

fba: std.heap.FixedBufferAllocator,

pub const capacity = unit.KB(4);

pub fn init(gpa: Allocator) !@This() {
    return .{ .fba = .init(try capacity.alloc(gpa)) };
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    gpa.free(self.fba.buffer);
    self.* = undefined;
}

pub fn reset(self: *@This()) void {
    self.fba.reset();
}

pub fn print(self: *@This(), comptime fmt: []const u8, args: anytype) ![]u8 {
    return std.fmt.allocPrint(self.fba.allocator(), fmt, args);
}

pub fn free(self: *@This(), buf: []u8) void {
    self.fba.allocator().free(buf);
}
