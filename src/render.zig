const std = @import("std");
const assert = std.debug.assert;

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

const core = @import("core");

const log = std.log.scoped(.gfx_render);

pub const ch_size: math.Point_u32 = .{ 30, 64 };
pub const cells: math.Point_u32 = .{ 120, 32 };
pub const font_atlas_size: math.Point_u32 = blk: {
    var r = ch_size;
    math.point_u32.scale(&r, 16);
    break :blk r;
};
pub const surf_size: math.Point_u32 = blk: {
    var r = ch_size;
    math.point_u32.mul(&r, &cells);
    break :blk r;
};

pub const CellState = [2]math.Vector4;

pub fn createGamePipeline(loader: *gfx.Loader) !void {
    const vert = loader.renderer.shaders.get("system/screen.vert");
    const game_frag = try loader.loadShader(.fragment, "game/screen.frag");
    const frame_frag = try loader.loadShader(.fragment, "game/print_frame.frag");
    _ = try loader.renderer.createGraphicsPipeline("game_screen", &.{
        .vertex_shader = vert,
        .fragment_shader = game_frag,
        .target_info = .{
            .color_target_descriptions = &.{
                .{ .format = .hdr_f, .blend_state = .blend },
            },
        },
    });
    _ = try loader.renderer.createGraphicsPipeline("game_frame", &.{
        .vertex_shader = vert,
        .fragment_shader = frame_frag,
        .target_info = .{
            .color_target_descriptions = &.{
                .{ .format = .default, .blend_state = .default },
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
    passes: []const gfx.pass.Interface,
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
    const game_pipeline = self.pipelines.graphics.get("game_screen");
    const blend_pipeline = self.pipelines.graphics.get("blend");
    // const render_pipeline = self.pipelines.graphics.get("render");
    const frame_buffer = self.storage_bufs.get("frame_buffer");
    const font_atlas = self.textures.get("font_atlas");
    const game_screen = self.textures.get("game_screen");
    const messages_buffer = self.textures.get("messages_buffer");
    const output_buffer = self.textures.get("output_buffer");
    const screen_buffer = self.textures.get("screen_buffer");
    const font_atlas_sampler = self.samplers.get("nearest_clamp_to_edge");
    const screen_sampler = self.samplers.get("bilinear_clamp_to_edge");

    const fa = allocators.frame();

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

    const win_size = math.point_u32.to(f32, &self.window.logicalSize());
    const wh_ratio = win_size[0] / win_size[1];
    const scr_size = math.point_u32.to(f32, &.{ surf_size[0], surf_size[1] });
    const scr_ratio = scr_size[0] / scr_size[1];
    const scr_scl: math.Point_f32 = if (wh_ratio > scr_ratio) .{
        wh_ratio / scr_ratio,
        1,
    } else .{
        1,
        scr_ratio / wh_ratio,
    };

    const uniform_buf = try fa.alloc(f32, 8);
    uniform_buf[0] = scr_size[0];
    uniform_buf[1] = scr_size[1];
    uniform_buf[2] = @bitCast(@as(u32, cells[0]));
    uniform_buf[3] = @bitCast(@as(u32, cells[1]));
    uniform_buf[4] = @bitCast(@as(u32, ch_size[0]));
    uniform_buf[5] = @bitCast(@as(u32, ch_size[1]));

    section.sub(.init).end();

    {
        var frame_pass = try command_buffer.renderPass(&.{
            .{ .texture = game_screen, .load_op = .clear, .store_op = .store },
        }, null);

        frame_pass.bindPipeline(frame_pipeline);
        command_buffer.pushUniformData(.fragment, 0, uniform_buf);
        try frame_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = font_atlas, .sampler = font_atlas_sampler },
        });
        try frame_pass.bindStorageBuffers(.fragment, 0, &.{frame_buffer.gpu_bufs.get(.vertex)});
        frame_pass.drawScreen();
        frame_pass.end();
    }
    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = screen_buffer, .load_op = .clear, .store_op = .store },
        }, null);

        render_pass.bindPipeline(game_pipeline);
        command_buffer.pushUniformData(.fragment, 0, &scr_scl);
        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = game_screen, .sampler = screen_sampler },
        });
        render_pass.drawScreen();
        render_pass.end();
    }

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = screen_buffer, .load_op = .load, .store_op = .store },
        }, null);

        render_pass.bindPipeline(blend_pipeline);
        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = messages_buffer, .sampler = screen_sampler },
        });
        render_pass.drawScreen();
        render_pass.end();
    }

    // They are swapped in opposite order first run
    // src -> screen_buffer
    // dst -> output_buffer
    var src_buf = output_buffer;
    var dst_buf = screen_buffer;
    for (passes, 0..) |tex_pass, n| {
        std.mem.swap(gfx.GPUTexture, &src_buf, &dst_buf);
        try tex_pass.render(
            self,
            command_buffer,
            src_buf,
            if (n == passes.len - 1) swapchain else dst_buf,
        );
    }

    // {
    //     var render_pass = try command_buffer.renderPass(&.{
    //         .{ .texture = swapchain, .load_op = .clear, .store_op = .store },
    //     }, null);
    //
    //     render_pass.bindPipeline(render_pipeline);
    //     command_buffer.pushUniformData(.fragment, 0, &self.settings.uniformBuffer());
    //     try render_pass.bindSamplers(.fragment, 0, &.{
    //         .{ .texture = output_buffer, .sampler = screen_sampler },
    //         .{ .texture = lut_map, .sampler = lut_sampler },
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
            // {
            //     var render_pass = try command_buffer.renderPass(&.{
            //         .{ .texture = swapchain, .load_op = .load, .store_op = .store },
            //     }, null);
            //
            //     const ui_settings: Renderer.Settings = .{
            //         .config = .{
            //             .has_srgb = true,
            //         },
            //     };
            //     render_pass.bindPipeline(render_pipeline);
            //     command_buffer.pushUniformData(.fragment, 0, &ui_settings.uniformBuffer());
            //     try render_pass.bindSamplers(.fragment, 0, &.{
            //         .{ .texture = output_buffer, .sampler = screen_sampler },
            //         .{ .texture = lut_map, .sampler = lut_sampler },
            //     });
            //     render_pass.drawScreen();
            //     render_pass.end();
            // }
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
