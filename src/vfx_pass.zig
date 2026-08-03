const std = @import("std");
const assert = std.debug.assert;

const zengine = @import("zengine");
const gfx = zengine.gfx;

const log = std.log.scoped(.pass_deathly_grayscale);

pub fn init(loader: *gfx.Loader) !void {
    const deathly_grayscale_frag = try loader.loadShader(.fragment, "game/vfx.frag");
    const screen_vert = loader.renderer.shaders.get("system/screen.vert");

    var pipeline: gfx.GPUGraphicsPipeline.CreateInfo = .{
        .vertex_shader = screen_vert,
        .fragment_shader = deathly_grayscale_frag,
        .target_info = .{
            .color_target_descriptions = &.{
                .{ .format = .hdr_f },
            },
        },
    };

    _ = try loader.renderer.createGraphicsPipeline("vfx_pass", &pipeline);
}

pub fn render(
    _: ?*anyopaque,
    renderer: *const gfx.Renderer,
    command_buffer: gfx.GPUCommandBuffer,
    src: gfx.GPUTexture,
    dst: gfx.GPUTexture,
) !void {
    const pipeline = renderer.pipelines.graphics.get("vfx_pass");
    const sampler = renderer.samplers.get("bilinear_clamp_to_edge");

    var uniform_buffer: [4]f32 = @splat(0);
    const win_size = renderer.engine.windows.get("main").logicalSize();
    const time_s = zengine.global.timeSinceStart().toFloat().toValue(.s);
    uniform_buffer[0] = @floatFromInt(win_size[0]);
    uniform_buffer[1] = @floatFromInt(win_size[1]);
    uniform_buffer[2] = @floatCast(time_s);

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = dst, .load_op = .dont_care, .store_op = .store },
        }, null);
        defer render_pass.end();

        render_pass.bindPipeline(pipeline);

        command_buffer.pushUniformData(.fragment, 0, &uniform_buffer);
        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = src, .sampler = sampler },
        });

        render_pass.drawScreen();
    }
}

pub fn interface() gfx.pass.Interface {
    return .{
        .ptr = null,
        .renderFn = &render,
    };
}
