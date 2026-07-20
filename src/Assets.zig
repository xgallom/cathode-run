const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Subdir = enum {
    music,
    samples,
};

aa: Allocator,
asset_path: []const u8,

// Requires arena
pub fn init(aa: Allocator) !@This() {
    const exe_path = try std.fs.selfExeDirPathAlloc(aa);
    const asset_path = try std.fs.path.join(aa, &.{ exe_path, "..", "assets" });
    return .{ .aa = aa, .asset_path = asset_path };
}

pub fn assetPath(self: *const @This(), subdir: Subdir, filename: []const u8) ![:0]const u8 {
    return std.fs.path.joinZ(self.aa, &.{ self.asset_path, subdirPath(subdir), filename });
}

fn subdirPath(subdir: Subdir) []const u8 {
    return switch (subdir) {
        .music => "music",
        .samples => "samples",
    };
}
