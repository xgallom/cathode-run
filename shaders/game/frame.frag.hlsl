#include <zengine.hlsl>

struct CellState {
    float4 clr_bg;
    float4 clr_fg;
};

cbuffer FragUniformBuffer : register(b0, space3) {
    float2 scr_res;
}

Texture2D<float4> FontAtlas : register(t0, space2);
SamplerState FontAtlasSampler  : register(s0, space2);
StructuredBuffer<CellState> FrameBuffer: register(t1, space2);

static const float2 cell_size = float2(30.0, 64.0);
static const float2 inv_cell_size = float2(1.0/30.0, 1.0/64.0);
static const float2 inv_atlas_size = float2(1.0/(16.0*30.0), 1.0/(16.0*64.0));
static const uint frame_w = 120;
static const uint frame_h = 32;

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    float2 uv = screen_pos * 0.5 + 0.5;
    float2 pixel_pos = uv * scr_res;
    float2 cell_f = pixel_pos * inv_cell_size;
    uint cell_x = (uint)cell_f.x;
    uint cell_y = (uint)cell_f.y;

    if (cell_x >= frame_w || cell_y >= frame_h) return float4(0, 0, 0, 0);

    float2 cell_local_pixel = pixel_pos - float2(cell_x, cell_y) * cell_size;
    uint cell_index = cell_y * frame_w + cell_x;
    CellState cell_state = FrameBuffer[cell_index];
    uint ch = (uint)cell_state.clr_bg.w;

    uint atlas_cell_x = ch % 16;
    uint atlas_cell_y = ch / 16;

    float2 atlas_pixel_pos = float2(atlas_cell_x, atlas_cell_y) * cell_size + cell_local_pixel;
    float2 atlas_uv = atlas_pixel_pos * inv_atlas_size;
    float4 text_color = FontAtlas.Sample(FontAtlasSampler, atlas_uv);
    return float4(lerp(cell_state.clr_bg.rgb, cell_state.clr_fg.rgb, text_color.rgb), 1);
}

