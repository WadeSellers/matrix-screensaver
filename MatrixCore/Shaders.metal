#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

struct ColumnState {
    float headRow;
    float speed;
    uint  frameCounter;
    uint  seed;
};

struct GridUniforms {
    uint  columnCount;
    uint  rowCount;
    float cellSize;
    float aspectFix;
    float2 viewportSize;
    uint  glyphCount;
    uint  cellsPerRow;
};

vertex VSOut vertex_fullscreen(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    VSOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = pos;
    return out;
}

static uint hash3(uint a, uint b, uint c) {
    a = (a ^ 61u) ^ (a >> 16);
    a = a + (a << 3);
    a = a ^ (a >> 4);
    a = a * 0x27d4eb2du;
    a = a ^ (a >> 15);
    a = a ^ (b * 73856093u) ^ (c * 83492791u);
    return a;
}

static float3 trailColor(float trailDist, float trailLength) {
    if (trailDist < 0.5) {
        return float3(0.87, 1.0, 0.87); // #DDFFDD head
    }
    constexpr float3 c1 = float3(0.0, 1.0, 0.4);     // #00FF66
    constexpr float3 c2 = float3(0.0, 0.53, 0.2);    // #008833
    constexpr float3 c3 = float3(0.0, 0.2, 0.067);   // #003311
    constexpr float3 c4 = float3(0.0, 0.0, 0.0);

    float t = trailDist;
    if (t < 8.0) {
        return mix(c1, c2, (t - 1.0) / 7.0);
    } else if (t < 16.0) {
        return mix(c2, c3, (t - 8.0) / 8.0);
    }
    float fadeRange = max(trailLength - 16.0, 1.0);
    return mix(c3, c4, clamp((t - 16.0) / fadeRange, 0.0, 1.0));
}

fragment float4 fragment_columns(
    VSOut in [[stage_in]],
    constant GridUniforms &grid [[buffer(0)]],
    constant ColumnState *columns [[buffer(1)]],
    texture2d<float> glyphAtlas [[texture(0)]]
) {
    float pixelX = in.uv.x * grid.viewportSize.x;
    float pixelY = (1.0 - in.uv.y) * grid.viewportSize.y;

    uint col = uint(pixelX / grid.cellSize);
    uint row = uint(pixelY / grid.cellSize);

    if (col >= grid.columnCount || row >= grid.rowCount) {
        return float4(0.0);
    }

    ColumnState s = columns[col];

    float trailLength = 12.0 + float(s.seed % 9u);
    float trailDist = s.headRow - float(row);

    if (trailDist < 0.0 || trailDist > trailLength) {
        return float4(0.0);
    }

    bool isHead = (trailDist < 0.5);
    uint frameBucket = isHead ? (s.frameCounter / 3u) : 0u;
    uint glyphIdx = hash3(col, row, s.seed ^ frameBucket) % grid.glyphCount;

    uint atlasCol = glyphIdx % grid.cellsPerRow;
    uint atlasRow = glyphIdx / grid.cellsPerRow;

    float cellU = fract(pixelX / grid.cellSize);
    float cellV = fract(pixelY / grid.cellSize);

    float atlasU = (float(atlasCol) + cellU) / float(grid.cellsPerRow);
    float atlasV = (float(atlasRow) + cellV) / float(grid.cellsPerRow);

    constexpr sampler s_atlas(filter::linear, address::clamp_to_edge);
    float alpha = glyphAtlas.sample(s_atlas, float2(atlasU, atlasV)).r;

    float3 color = trailColor(trailDist, trailLength);

    bool isStammer = (s.seed % 5u) == 0u;
    if (isStammer) {
        float stammerRow = floor(fmod(float(s.seed >> 8) / 7.0, trailLength - 1.0)) + 1.0;
        if (abs(trailDist - stammerRow) < 0.5) {
            color += float3(0.25, 0.4, 0.25);
        }
    }

    return float4(color * alpha, 1.0);
}

// ===== Bloom + CRT pipeline =====
// 1. fragment_bloom_extract: read scene, keep only pixels above a luminance
//    threshold, halve resolution as a side-effect via the smaller render target.
// 2. fragment_bloom_blur_h / _v: separable Gaussian, 9-tap, sigma~3 cells.
// 3. fragment_bloom_composite: scene + bloom*strength + optional CRT
//    (scanlines + vignette) to the drawable.

constant float kBloomThreshold = 0.55;

// 9-tap Gaussian kernel (sigma~2). Normalized so weights sum to ~1.
constant float kBlurWeights[9] = {
    0.027, 0.066, 0.123, 0.180, 0.207, 0.180, 0.123, 0.066, 0.028
};

struct BlurUniforms {
    float2 texelSize;   // 1/textureWidth, 1/textureHeight
    float2 _pad;
};

struct CompositeUniforms {
    float bloomStrength;     // 0..1, scales the bloom contribution
    float crtEnabled;        // 0 or 1; toggles scanlines + vignette
    float scanlineDarken;    // 0..1, how much the dark scanlines drop
    float vignetteAmount;    // 0..1, vignette intensity
    float2 viewportSize;     // pixels, used for scanline frequency
    float2 _pad;
};

fragment float4 fragment_bloom_extract(
    VSOut in [[stage_in]],
    texture2d<float> scene [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 c = scene.sample(s, float2(in.uv.x, 1.0 - in.uv.y)).rgb;
    float lum = dot(c, float3(0.299, 0.587, 0.114));
    float keep = smoothstep(kBloomThreshold, kBloomThreshold + 0.15, lum);
    return float4(c * keep, 1.0);
}

fragment float4 fragment_bloom_blur_h(
    VSOut in [[stage_in]],
    constant BlurUniforms &u [[buffer(0)]],
    texture2d<float> src [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float3 sum = float3(0.0);
    for (int i = -4; i <= 4; ++i) {
        float2 offset = float2(float(i) * u.texelSize.x, 0.0);
        sum += src.sample(s, uv + offset).rgb * kBlurWeights[i + 4];
    }
    return float4(sum, 1.0);
}

fragment float4 fragment_bloom_blur_v(
    VSOut in [[stage_in]],
    constant BlurUniforms &u [[buffer(0)]],
    texture2d<float> src [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float3 sum = float3(0.0);
    for (int i = -4; i <= 4; ++i) {
        float2 offset = float2(0.0, float(i) * u.texelSize.y);
        sum += src.sample(s, uv + offset).rgb * kBlurWeights[i + 4];
    }
    return float4(sum, 1.0);
}

fragment float4 fragment_bloom_composite(
    VSOut in [[stage_in]],
    constant CompositeUniforms &u [[buffer(0)]],
    texture2d<float> scene [[texture(0)]],
    texture2d<float> bloom [[texture(1)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float3 sceneColor = scene.sample(s, uv).rgb;
    float3 bloomColor = bloom.sample(s, uv).rgb;
    float3 color = sceneColor + bloomColor * u.bloomStrength;

    // Optional CRT pass: scanlines + soft vignette. Off by default.
    if (u.crtEnabled > 0.5) {
        // Crisp scanlines every 6 physical pixels — wide enough to read on
        // retina and at downsampled screenshot resolutions. floor(...) buckets
        // pixels; alternating groups are darkened.
        float band = floor(uv.y * u.viewportSize.y * (1.0 / 6.0));
        float scan = fmod(band, 2.0);  // 0 or 1
        float scanFactor = mix(1.0 - u.scanlineDarken, 1.0, scan);
        color *= scanFactor;

        // Vignette: radial darkening toward edges.
        float2 centered = uv - 0.5;
        float r2 = dot(centered, centered);
        float vignette = 1.0 - r2 * u.vignetteAmount * 1.6;
        color *= clamp(vignette, 0.0, 1.0);
    }

    return float4(color, 1.0);
}
