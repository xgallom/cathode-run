const std = @import("std");
const assert = std.debug.assert;

const zengine = @import("zengine");
const gfx = zengine.gfx;
const math = zengine.math;

const log = std.log.scoped(.pass_deathly_grayscale);

size: math.Point_u32,

pub fn render(
    self: *const @This(),
    renderer: *const gfx.Renderer,
    command_buffer: gfx.GPUCommandBuffer,
    src: gfx.GPUTexture,
    dst: gfx.GPUTexture,
) !void {
    const pipeline = renderer.pipelines.graphics.get("postfx");
    const sampler = renderer.samplers.get("bilinear_clamp_to_edge");

    var uniform_buffer: [4]f32 = @splat(0);
    const tex_size = self.size;
    const time_s = zengine.global.timeSinceStart().toFloat().toValue(.s);
    uniform_buffer[0] = @floatFromInt(tex_size[0]);
    uniform_buffer[1] = @floatFromInt(tex_size[1]);
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

pub fn interface(self: *const @This()) gfx.pass.Interface {
    return .{
        .ptr = @ptrCast(@constCast(self)),
        .renderFn = @ptrCast(&render),
    };
}
