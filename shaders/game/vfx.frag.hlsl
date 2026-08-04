cbuffer FragUniformBuffer : register(b0, space3) {
    float2 iResolution;
    float iTime;
}

Texture2D<float4> SrcBuffer : register(t0, space2);
SamplerState SrcSampler  : register(s0, space2);

// --- Terminal Parameters ---
static const float cells_x = 120;       // Cell width in terminal
static const float cells_y = 32;       // Cell height in terminal
static const float cell_w_px = 7.5;       // Cell width in terminal
static const float cell_h_px = 16.0;       // Cell height in terminal
static const float pixels_per_cell = 7.5; // How many pixels per character line
static const float scans_per_cell = 16.0;  // How many scanlines per character

// --- Configurable Parameters ---

static const float exposure = 1.0;        // Input exposure
static const float bootup_delay = 1.5;    // Time between starting the application and the screen
static const float bootup_time = 6.0;     // Time for the screen to turn on
static const float thermal_amt = 6.0;    // Strength of thermal instabilities
static const float hv_sag_amt = 3.00;     // Amount of high-voltage sag
static const float warp = 1.00;           // Strength of screen curvature
static const float convergence = 0.0020;  // How far the RGB beams separate at the edges
static const float tint_amt = 0.00;       // Monochrome tint intensity
static const float sat = 1.00;            // Saturation
static const float bloom_amt = 1.00;      // How intense the glow is
static const float bloom_pwr = 2.00;      // How non-linear is the blur
static const float bloom_radius = 1.5;    // How far the light scatters (in pixels)
static const float scanlines = 512.0;     // Number of horizontal scanlines
static const float scan_depth = 1.00;     // How dark the gaps get (0.0 to 1.0)
static const float sigma = 0.35;          // Beam focus thickness
static const float noise_amt = 0.0250;    // Static grain intensity
static const float vign_amt = 1.00;       // Vignette strength
static const float refl = 0.020;          // Glass glare intensity
static const float brightness = 1.00;     // Output brightness

// --- Configuration Flags ---

// Enable shader
#define SHADER_ENABLED

// Enable bootup
// #define BOOTUP_ENABLED

// Enable high-voltage sag
// #define HIGH_VOLTAGE_SAG_ENABLED

// Enable global illuminance sampling
// Shader always uses hex sampling
// #define GLOBAL_ILLUMINANCE_SAMPLING_ENABLED

// Enable thermal instability
// #define THERMAL_INSTABILITY_ENABLED

// Enable warping
#define WARPING_ENABLED

// Enable screen-space dithering
// #define DITHER_ENABLED

// Enable chromatic aberration
#define CHROMATIC_ABERRATION_ENABLED

// Enable horizontal scanlines
#define SCANLINES_ENABLED

// Enable automatic scanlines count
// Requires cell_w_px, cell_h_px and scans_per_cell
// Otherwise requies scanlines
#define AUTOMATIC_SCANLINES

// Enable bloom
#define BLOOM_ENABLED

// Pick a version of the bloom algorithm
// 0 - Fast (4-sample diagonal)
// 1 - Average (8-sample box)
// 2 - Best (13-sample hexagonal)
#define BLOOM_QUALITY 2

// If CHROMATIC_ABERRATION_ENABLED, sample colors separately
#define BLOOM_ABERRATED

// Enable noise
#define NOISE_ENABLED

// Enable vignette
#define VIGNETTE_ENABLED

// Enable glare
#define GLARE_ENABLED

// --- Implementation ---

static const float DITHER_MATRIX[40] = {
    0.0, 0.0, 1.0, 0.0,
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 1.0,
    1.0, 0.0, 1.0, 0.0,
    1.0, 1.0, 0.0, 1.0,
    0.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0,
    1.0, 1.0, 1.0, 1.0
};
static const float4 DITHER_INDEX = float4(0.20, 0.40, 0.60, 0.80);
static const float3 LUMA_WEIGHTS = float3(0.299, 0.587, 0.114);
static const float3 MONO_TINT = float3(0.2, 1.0, 0.8);
static const float2 DIAG_SAMPLES[4] = {
    float2(-1.0,-1.0), float2( 1.0,-1.0),
    float2(-1.0, 1.0), float2( 1.0, 1.0)
};
static const float2 BOX_SAMPLES[8] = {
    float2(-1.0,-1.0), float2( 0.0,-1.0), float2( 1.0,-1.0),
    float2(-1.0, 0.0),                  float2( 1.0, 0.0),
    float2(-1.0, 1.0), float2( 0.0, 1.0), float2( 1.0, 1.0)
};
static const float2 HEX_SAMPLES[13] = {
    float2( 0.0,     0.0),    // Center

    // Inner Ring (Radius ~ 0.35)
    float2( 0.0,     0.350),  // Top
    float2( 0.303,   0.175),  // Top Right
    float2( 0.303,  -0.175),  // Bottom Right
    float2( 0.0,    -0.350),  // Bottom
    float2(-0.303,  -0.175),  // Bottom Left
    float2(-0.303,   0.175),  // Top Left

    // Outerk Ring (Radius ~ 0.80)
    // Shifted angles slightly to fill the gaps
    float2( 0.0,     0.800),  // Top
    float2( 0.693,   0.400),  // Top Right
    float2( 0.693,  -0.400),  // Bottom Right
    float2( 0.0,    -0.800),  // Bottom
    float2(-0.693,  -0.400),  // Bottom Left
    float2(-0.693,   0.400)   // Top Left
};

void bloomLookup(
    out float3 mono_bloom, out float3 vga_bloom,
    in float2 uv, in float2 texel, float ca_offset
);
float estimateGlobalLuminance();
float random(float2 uv);
float3 sampleUv(float2 uv);
float3 tintLuma(float3 value, float3 tint);
float sampleLuma(float3 value);

float4 main(float2 fragCoord : TEX_COORD) : SV_Target
{
    float2 uv = fragCoord * 0.5 + 0.5;

#ifndef SHADER_ENABLED
    return float4(SrcBuffer.Sample(SrcSampler, uv).rgb, 1);

#else // SHADER_ENABLED

#ifdef HIGH_VOLTAGE_SAG_ENABLED
    float global_brightness = estimateGlobalLuminance();
    float hv_sag = global_brightness * hv_sag_amt;
#else
    float hv_sag = 0.0;
#endif

#ifdef THERMAL_INSTABILITY_ENABLED
    float thermal_wobble = 1.0 + 1.05 * sin(iTime / 10.0) + 0.859 * sin(iTime / 64.0) +
        0.9 * cos(iTime / 11.9);
    float ripple = 1.0 + 1.5 * sin(60.0 * iTime);
    float drift_period = (0.001 + bootup_delay) / 3.0;
    // (1.0 + exp(-iTime / drift_period))
    float drift = 1.0 + abs(
        2.00 * sin(60.0 * 1.0 * iTime) * exp(-iTime / 500.0)
    );
    float thermal = thermal_wobble * ripple * drift * thermal_amt;
#else
    float thermal = 1.0;
#endif
    float u_time = thermal * (1.0 + hv_sag);

#ifdef AUTOMATIC_SCANLINES
    uv.x -= 0.5;
    uv.x *= cell_w_px / pixels_per_cell;
    uv.x += 0.5;
    float2 cell_px = float2(pixels_per_cell, cell_h_px);
    float2 cells = float2(cells_x, cells_y);
    float2 cell_size = iResolution / cells;
    float2 cell_comp = float2(
        cell_size.y / cell_px.y * cell_px.x,
        cell_size.x / cell_px.x * cell_px.y);
    cell_px = float2(cell_size.x, cell_comp.y);
    if (cell_size.x > cell_comp.x) cell_px = float2(cell_comp.x, cell_size.y);

    float2 cells_px = cells * cell_px;
    float2 cells_to_fb = cells_px / iResolution.xy;
    float2 pad_uv = (iResolution.xy - cells_px) / (2.0 * iResolution.xy);
    float2 cell_uv = (uv - pad_uv) / cells_to_fb;
#else
    float2 cell_px = float2(1, 1);
    float2 cells = iResolution.xy;
    float2 cells_px = cells;
    float2 cells_to_fb = float2(1, 1);
    float2 pad_uv = float2(0, 0);
    float2 cell_uv = uv;
#endif

    float2 aspect = cells_px.xy / cells_px.y;
    float2 dc = (cell_uv - 0.5) * aspect;
    float2 dc_sq = dc * dc;

#ifdef WARPING_ENABLED
    float2 u_warp = 0.00001 * float2(sin(1440.0 * iTime), cos(1441.0 * iTime)) * u_time;
    float2 warp_mul = float2(
        1.0 + dc_sq.y * (0.03 * warp * (1.0 + 0.05 * hv_sag)),
        1.0 + dc_sq.x * (0.04 * warp * (1.0 + 0.05 * hv_sag))
    );
    cell_uv -= 0.5 + u_warp;
    cell_uv *= warp_mul;
    cell_uv += 0.5;
    uv = cell_uv * cells_to_fb + pad_uv;
#endif

#ifdef SCANLINES_ENABLED
#ifdef AUTOMATIC_SCANLINES
    float scanlines = cells.y * scans_per_cell;
#endif // AUTOMATIC_SCANLINES
    float raw_phase = cell_uv.y * scanlines;
    float line_uv = frac(raw_phase) - 0.5;
    float snapped_cell_y = (floor(raw_phase) + 0.5) / scanlines;
    float2 mono_uv = float2(uv.x, snapped_cell_y * cells_to_fb.y + pad_uv.y);
#else // SCANLINES_ENABLED
    float2 mono_uv = uv;
#endif // SCANLINES_ENABLED

    float2 bounds = step(float2(0, 0), uv) * step(uv, float2(1, 1));
    float mask = bounds.x * bounds.y;

    float3 mono_color = sampleUv(mono_uv);

#ifdef CHROMATIC_ABERRATION_ENABLED
    float ca_offset = convergence * (1.0 + 0.002 * u_time) * dot(dc, dc);
    float3 vga_color;
    vga_color.r = sampleUv(mono_uv + float2(ca_offset, 0.0)).r;
    vga_color.g = mono_color.g;
    vga_color.b = sampleUv(mono_uv - float2(ca_offset, 0.0)).b;
#else
    float ca_offset = 0.0;
    float3 vga_color = mono_color;
#endif

    float3 tint = lerp(float3(1, 1, 1), MONO_TINT, tint_amt);
    float3 color = lerp(tintLuma(mono_color, tint), vga_color, sat);

#ifdef DITHER_ENABLED
    float max_c = max(vga_color.r, max(vga_color.g, max(vga_color.b, 0.0001)));
    int dither_x = int(mod(floor(fragCoord.x) / 4.0, 4.0));
    int dither_y = int(mod(floor(fragCoord.y) / 4.0, 2.0));
    float4 dither_acc = step(DITHER_INDEX, float4(max_c));
    int dither_idx = int(dither_acc.x + dither_acc.y + dither_acc.z + dither_acc.w);
    float dither = DITHER_MATRIX[dither_x + dither_y * 4 + dither_idx * 8];
    float is_full = step(0.5, max_c);
    color = color * ((1.0 - is_full) * dither * 0.66 / max_c + is_full);
#endif

#ifdef SCANLINES_ENABLED
    float falloff = exp(-(line_uv * line_uv) / (2.0 * sigma * sigma));
    float intensity = lerp(1.0 - scan_depth, 1.0, falloff);
    float3 scanned = color * intensity;
#else
    float3 scanned = color;
#endif

#ifdef BLOOM_ENABLED
    float3 mono_bloom;
    float3 vga_bloom;
    bloomLookup(mono_bloom, vga_bloom, uv, 1.0 / iResolution.xy, ca_offset);
    float3 bloom = lerp(tintLuma(mono_bloom, tint), vga_bloom, sat);
    scanned += pow(bloom, float3(bloom_pwr.xxx)) * bloom_amt;
#endif

#ifdef NOISE_ENABLED
    scanned += (random(uv + iTime) - 0.5) * noise_amt * (1.0 + 0.015 * u_time);
#endif

#ifdef VIGNETTE_ENABLED
    float vignette = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
    vignette = saturate(pow(16.0 * vignette, 0.25));
    scanned *= lerp(1.0, vignette, vign_amt);
#endif

#ifdef GLARE_ENABLED
    float glare = max(0.0, 1.0 - distance(uv, float2(0.5, 0.0)) * 1.2);
    scanned += glare * refl;
#endif

    return float4(saturate((scanned * brightness) * mask), 1.0);
#endif // SHADER_ENABLED
}

void bloomLookup(
    out float3 mono_bloom, out float3 vga_bloom,
    in float2 uv, in float2 texel, float ca_offset
) {
#if !defined(CHROMATIC_ABERRATION_ENABLED) || !defined(BLOOM_ABERRATED)
#if BLOOM_QUALITY == 0
    mono_bloom = float3(0, 0, 0);
    for (int i = 0; i < 4; i++) {
        float2 offset = DIAG_SAMPLES[i] * texel * bloom_radius;
        float2 sample_uv = uv + offset;
        mono_bloom += sampleUv(sample_uv);
    }
    mono_bloom /= 4.0;
    vga_bloom = mono_bloom;
#elif BLOOM_QUALITY == 1
    mono_bloom = float3(0, 0, 0);
    for (int i = 0; i < 8; i++) {
        float2 offset = BOX_SAMPLES[i] * texel * bloom_radius;
        float2 sample_uv = uv + offset;
        mono_bloom += sampleUv(sample_uv);
    }
    mono_bloom /= 8.0;
    vga_bloom = mono_bloom;
#elif BLOOM_QUALITY == 2
    mono_bloom = float3(0, 0, 0);
    for (int i = 0; i < 13; i++) {
        float2 offset = HEX_SAMPLES[i] * texel * bloom_radius;
        float2 sample_uv = uv + offset;
        mono_bloom += sampleUv(sample_uv);
    }
    mono_bloom /= 13.0;
    vga_bloom = mono_bloom;
#else // BLOOM_QUALITY
#error "Invalid value for BLOOM_QUALITY"
#endif // BLOOM_QUALITY
#else // CHROMATIC_ABERRATION_ENABLED
#if BLOOM_QUALITY == 0
    mono_bloom = float3(0, 0, 0);
    vga_bloom = float3(0, 0, 0);
    float2 r_offset = float2(ca_offset, 0.0);
    float2 b_offset = float2(-ca_offset, 0.0);
    for (int i = 0; i < 4; i++) {
        float2 offset = DIAG_SAMPLES[i] * texel * bloom_radius;
        float2 sample_uv = uv + offset;
        float3 center_bloom = sampleUv(sample_uv);
        vga_bloom.r += sampleUv(sample_uv + r_offset).r;
        vga_bloom.g += center_bloom.g;
        vga_bloom.b += sampleUv(sample_uv + b_offset).b;
        mono_bloom += center_bloom;
    }
    mono_bloom /= 4.0;
    vga_bloom /= 4.0;
#elif BLOOM_QUALITY == 1
    mono_bloom = float3(0, 0, 0);
    vga_bloom = float3(0, 0, 0);
    float2 r_offset = float2(ca_offset, 0.0);
    float2 b_offset = float2(-ca_offset, 0.0);
    for (int i = 0; i < 8; i++) {
        float2 offset = BOX_SAMPLES[i] * texel * bloom_radius;
        float2 sample_uv = uv + offset;
        float3 center_bloom = sampleUv(sample_uv);
        vga_bloom.r += sampleUv(sample_uv + r_offset).r;
        vga_bloom.g += center_bloom.g;
        vga_bloom.b += sampleUv(sample_uv + b_offset).b;
        mono_bloom += center_bloom;
    }
    mono_bloom /= 8.0;
    vga_bloom /= 8.0;
#elif BLOOM_QUALITY == 2
    mono_bloom = float3(0, 0, 0);
    vga_bloom = float3(0, 0, 0);
    float2 r_offset = float2(ca_offset, 0.0);
    float2 b_offset = float2(-ca_offset, 0.0);
    for (int i = 0; i < 13; i++) {
        float2 offset = HEX_SAMPLES[i] * texel * bloom_radius;
        float2 sample_uv = uv + offset;
        float3 center_bloom = sampleUv(sample_uv);
        vga_bloom.r += sampleUv(sample_uv + r_offset).r;
        vga_bloom.g += center_bloom.g;
        vga_bloom.b += sampleUv(sample_uv + b_offset).b;
        mono_bloom += center_bloom;
    }
    mono_bloom /= 13.0;
    vga_bloom /= 13.0;
#else // BLOOM_QUALITY
#error "Invalid value for BLOOM_QUALITY"
#endif // BLOOM_QUALITY
#endif // CHROMATIC_ABERRATION_ENABLED
}

float estimateGlobalLuminance() {
#ifdef GLOBAL_ILLUMINANCE_SAMPLING_ENABLED
    float luma_acc = 0.0;
    for (int i = 0; i < 13; i++) {
        luma_acc += sampleLuma(sampleUv(float2(0.5) + (HEX_SAMPLES[i] * 0.5)));
    }
    return luma_acc / 13.0;
#else
    return 0.15;
#endif
}

float random(float2 uv) {
    return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453123);
}

float3 sampleUv(float2 uv) {
#ifdef BOOTUP_ENABLED
    float bootup = saturate(1.0 - exp((bootup_delay - iTime) / max(bootup_time / 3.0, 0.001)));
#else
    float bootup = 1.0;
#endif
    return exposure * bootup * SrcBuffer.Sample(SrcSampler, uv).rgb;
}

float3 tintLuma(float3 value, float3 tint) {
    return dot(value, LUMA_WEIGHTS) * tint;
}

float sampleLuma(float3 value) {
    return dot(value, LUMA_WEIGHTS);
}


