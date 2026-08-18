const std = @import("std");
const assert = std.debug.assert;

const core = @import("core");
const zengine = @import("zengine");
const allocators = zengine.allocators;
const global = zengine.global;
const math = zengine.math;
const gfx_options = zengine.options.gfx;
const perf = zengine.perf;
const ui_mod = zengine.ui;
const gfx = zengine.gfx;
const Error = gfx.Error;
const Renderer = gfx.Renderer;
const sections = Renderer.sections;

const log = std.log.scoped(.gfx_render);

// WARN: When changing these, also change them in the shaders!

pub const ch_size: math.Point_u32 = .{ 30, 64 };
pub const cells: math.Point_u32 = .{ 120, 32 };
pub const font_atlas_size: math.Point_u32 = blk: {
    var r = ch_size;
    math.point_u32.scale(&r, 16);
    break :blk r;
};
pub const frame_size: math.Point_u32 = blk: {
    var r = ch_size;
    math.point_u32.mul(&r, &cells);
    break :blk r;
};

pub const CellState = [2]math.Vector4;
pub const Pass = enum { scale, postfx, letterbox, render };

pub fn createGamePipeline(loader: *gfx.Loader) !void {
    const vert = loader.renderer.shaders.get("system/screen.vert");
    const frame_frag = try loader.loadShader(.fragment, "game/frame.frag");
    const postfx_frag = try loader.loadShader(.fragment, "game/postfx.frag");

    _ = try loader.renderer.createGraphicsPipeline("game_frame", &.{
        .vertex_shader = vert,
        .fragment_shader = frame_frag,
        .target_info = .{
            .color_target_descriptions = &.{
                .{ .format = .default },
            },
        },
    });
    _ = try loader.renderer.createGraphicsPipeline("postfx", &.{
        .vertex_shader = vert,
        .fragment_shader = postfx_frag,
        .target_info = .{
            .color_target_descriptions = &.{
                .{ .format = .hdr_f },
            },
        },
    });
}

pub fn fontAtlasOffset(c: u8) math.Point_u32 {
    return .{ ch_size[0] * (c % 16), ch_size[1] * (c / 16) };
}

pub fn renderScreen(
    self: *const Renderer,
    ui_ptr: ?*ui_mod.UI,
    passes: std.EnumArray(Pass, gfx.pass.Interface),
    fence: ?*gfx.GPUFence,
) !bool {
    const section = Renderer.sections.sub(.render);
    section.begin();

    if (fence) |f| {
        if (f.isValid()) {
            try self.gpu_device.wait(.any, &.{f.*});
            self.gpu_device.release(f);
        }
    }

    const frame_pipeline = self.pipelines.graphics.get("game_frame");
    const frame_buffer = self.storage_bufs.get("frame_buffer");
    const font_atlas = self.textures.get("font_atlas");
    const frame_tex = self.textures.get("frame_buffer");
    // const messages_buffer = self.textures.get("messages_buffer");
    const output_buffer = self.textures.get("output_buffer");
    const screen_buffer = self.textures.get("screen_buffer");
    const render_buffer = self.textures.get("render_buffer");
    const font_atlas_sampler = self.samplers.get("nearest_clamp_to_edge");

    section.sub(.acquire).begin();
    var command_buffer = try self.gpu_device.commandBuffer();
    errdefer command_buffer.cancel() catch {};
    const swapchain = try command_buffer.swapchainTextureWait(self.window);
    section.sub(.acquire).end();

    if (!swapchain.isValid()) {
        log.info("skip draw", .{});
        section.pop();
        return false;
    }

    section.sub(.init).begin();
    section.sub(.init).end();

    const frame_size_f32 = math.point_f32.from(u32, &frame_size);
    {
        var frame_pass = try command_buffer.renderPass(&.{
            .{ .texture = frame_tex, .load_op = .clear, .store_op = .store },
        }, null);

        frame_pass.bindPipeline(frame_pipeline);
        command_buffer.pushUniformData(.fragment, 0, &frame_size_f32);
        try frame_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = font_atlas, .sampler = font_atlas_sampler },
        });
        try frame_pass.bindStorageBuffers(.fragment, 0, &.{frame_buffer.gpu_bufs.get(.vertex)});
        frame_pass.drawScreen();
        frame_pass.end();
    }

    try passes.get(.scale).render(self, command_buffer, frame_tex, screen_buffer);
    try passes.get(.postfx).render(self, command_buffer, screen_buffer, output_buffer);
    try passes.get(.letterbox).render(self, command_buffer, output_buffer, render_buffer);
    try passes.get(.render).render(self, command_buffer, render_buffer, swapchain);

    // {
    //     var render_pass = try command_buffer.renderPass(&.{
    //         .{ .texture = screen_buffer, .load_op = .load, .store_op = .store },
    //     }, null);
    //
    //     render_pass.bindPipeline(blend_pipeline);
    //     try render_pass.bindSamplers(.fragment, 0, &.{
    //         .{ .texture = messages_buffer, .sampler = screen_sampler },
    //     });
    //     render_pass.drawScreen();
    //     render_pass.end();
    // }

    if (ui_ptr) |ui| {
        section.sub(.ui).begin();
        if (ui.render_ui) {
            const render_pass = gfx.pass.Render{
                .config = .{
                    .has_srgb = true,
                    .clear = false,
                },
            };
            try ui.submitPass(command_buffer, screen_buffer);
            try render_pass.render(self, command_buffer, screen_buffer, swapchain);
        }
        section.sub(.ui).end();
    }

    section.sub(.submit).begin();
    log.debug("submit command buffer", .{});
    if (fence) |f| {
        assert(!f.isValid());
        f.* = try command_buffer.submitFence();
    } else try command_buffer.submit();
    section.sub(.submit).end();

    section.end();
    return true;
}

const Sizes = struct { win_size: math.Point_u32, tex_size: math.Point_u32 };
pub fn createTextures(self: *Renderer) !Sizes {
    const win_size = self.window.pixelSize();
    const tex_size = calculateTextureSize(win_size);

    log.debug(
        "create textures: {}x{}, {}x{}",
        .{ win_size[0], win_size[1], tex_size[0], tex_size[1] },
    );

    _ = try self.createTexture("screen_buffer", &.{
        .type = .@"2D",
        .format = .hdr_f,
        .usage = .initMany(&.{ .sampler, .color_target }),
        .size = tex_size,
    });

    _ = try self.createTexture("output_buffer", &.{
        .type = .@"2D",
        .format = .hdr_f,
        .usage = .initMany(&.{ .sampler, .color_target }),
        .size = tex_size,
    });

    _ = try self.createTexture("render_buffer", &.{
        .type = .@"2D",
        .format = .hdr_f,
        .usage = .initMany(&.{ .sampler, .color_target }),
        .size = win_size,
    });

    return .{ .win_size = win_size, .tex_size = tex_size };
}

pub fn resizeTextures(self: *Renderer) !Sizes {
    self.deleteTexture("screen_buffer");
    self.deleteTexture("output_buffer");
    self.deleteTexture("render_buffer");
    return try createTextures(self);
}

// 4112x2580
// 4535x2340
pub fn calculateTextureSize(win_size: math.Point_u32) math.Point_u32 {
    const comp_size: math.Point_u32 = .{
        win_size[1] * frame_size[0] / frame_size[1],
        win_size[0] * frame_size[1] / frame_size[0],
    };
    log.debug("{}x{}", .{ comp_size[0], comp_size[1] });
    return if (comp_size[0] >= win_size[0]) .{
        win_size[0],
        comp_size[1],
    } else .{
        comp_size[0],
        win_size[1],
    };
}
