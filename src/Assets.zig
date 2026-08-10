const std = @import("std");
const Allocator = std.mem.Allocator;

const zengine = @import("zengine");
const global = zengine.global;

pub const Subdir = enum {
    music,
    samples,
};

aa: Allocator,
cache: std.EnumArray(Subdir, std.StringHashMapUnmanaged([:0]const u8)) = .initFill(.empty),

// Requires arena
pub fn init(aa: Allocator) !@This() {
    return .{ .aa = aa };
}

pub fn assetPath(self: *@This(), subdir: Subdir, filename: []const u8) ![:0]const u8 {
    const cache = self.cache.getPtr(subdir);
    const r = try cache.getOrPut(self.aa, filename);
    if (!r.found_existing) r.value_ptr.* = try std.fs.path.joinZ(self.aa, &.{
        global.assetsPath(),
        subdirPath(subdir),
        filename,
    });
    return r.value_ptr.*;
}

fn subdirPath(subdir: Subdir) []const u8 {
    return switch (subdir) {
        .music => "music",
        .samples => "samples",
    };
}
