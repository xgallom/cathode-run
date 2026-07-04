const std = @import("std");
const log = std.log.scoped(.unit);
const Allocator = std.mem.Allocator;

pub const Bytes = extern struct {
    v: usize,

    pub fn available(self: @This(), used: usize) usize {
        return self.v - used;
    }

    pub fn alloc(self: @This(), gpa: Allocator) ![]u8 {
        log.debug("alloc {}B", .{self.v});
        return gpa.alloc(u8, self.v);
    }

    pub fn free(self: @This(), gpa: Allocator, ptr: [*]u8) void {
        log.debug("free {}B", .{self.v});
        gpa.free(ptr[0..self.v]);
    }

    pub fn B(val: usize) @This() {
        return .{ .v = val };
    }

    // We are lying, this is KiB. MISCHIEF! >:3
    pub fn KB(val: usize) @This() {
        return B(val << 10);
    }

    pub fn MB(val: usize) @This() {
        return .KB(val << 10);
    }

    pub fn GB(val: usize) @This() {
        return .MB(val << 10);
    }
};

pub const Microsecs = extern struct {
    v: u64,

    pub fn us(val: u64) @This() {
        return .{ .v = val };
    }

    pub fn ms(val: u64) @This() {
        return .us(val * std.time.us_per_ms);
    }

    pub fn s(val: u64) @This() {
        return .ms(val * std.time.ms_per_s);
    }

    pub fn toNs(self: @This()) u64 {
        return self.v * std.time.ns_per_us;
    }
};

pub const KB = Bytes.KB;
pub const MB = Bytes.MB;
pub const GB = Bytes.GB;
pub const us = Microsecs.us;
pub const ms = Microsecs.ms;
pub const s = Microsecs.s;
