#include <zengine.hlsl>

struct CellState {
    float4 clr_bg;
    float4 clr_fg;
};

cbuffer FragUniformBuffer : register(b0, space3) {
    float2 scr_res;
    uint frame_w;
    uint frame_h;
    uint cell_w;
    uint cell_h;
}

Texture2D<float4> FontAtlas : register(t0, space2);
SamplerState FontAtlasSampler  : register(s0, space2);
StructuredBuffer<CellState> FrameBuffer: register(t1, space2);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    float2 uv = screen_pos * 0.5 + 0.5;
    float2 pixel_pos = uv * scr_res;
    uint cell_x = (uint)(pixel_pos.x / (float)cell_w);
    uint cell_y = (uint)(pixel_pos.y / (float)cell_h);

    if (cell_x >= frame_w || cell_y >= frame_h) return float4(0, 0, 0, 0);

    float2 cell_local_pixel = float2(pixel_pos.x % (float)cell_w, pixel_pos.y % (float)cell_h);
    uint cell_index = cell_y * frame_w + cell_x;
    CellState cell_state = FrameBuffer[cell_index];
    uint ch = (uint)cell_state.clr_bg.w;

    uint atlas_cell_x = ch % 16;
    uint atlas_cell_y = ch / 16;

    float2 atlas_pixel_pos = float2(atlas_cell_x * cell_w, atlas_cell_y * cell_h) + cell_local_pixel;
    float2 atlas_uv = atlas_pixel_pos / float2(16 * cell_w, 16 * cell_h);
    float4 text_color = FontAtlas.Sample(FontAtlasSampler, atlas_uv);
    return float4(lerp(cell_state.clr_bg.rgb, cell_state.clr_fg.rgb, text_color.rgb), 1);
}

