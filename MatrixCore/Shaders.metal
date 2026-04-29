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

// Stable per-(col,row,bucket) hash. PCG-style scrambling.
static uint hash3(uint a, uint b, uint c) {
    a = (a ^ 61u) ^ (a >> 16);
    a = a + (a << 3);
    a = a ^ (a >> 4);
    a = a * 0x27d4eb2du;
    a = a ^ (a >> 15);
    a = a ^ (b * 73856093u) ^ (c * 83492791u);
    return a;
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

    // Cell hasn't been touched yet — leave black.
    if (float(row) > s.headRow) {
        return float4(0.0);
    }

    // Glyph swap rule: bucket frameCounter into groups of 3 frames so the
    // glyph holds for ~3 frames before potentially picking a new one.
    uint frameBucket = s.frameCounter / 3u;
    uint glyphIdx = hash3(col, row, s.seed ^ frameBucket) % grid.glyphCount;

    uint atlasCol = glyphIdx % grid.cellsPerRow;
    uint atlasRow = glyphIdx / grid.cellsPerRow;

    float cellU = fract(pixelX / grid.cellSize);
    float cellV = fract(pixelY / grid.cellSize);

    float atlasU = (float(atlasCol) + cellU) / float(grid.cellsPerRow);
    float atlasV = (float(atlasRow) + cellV) / float(grid.cellsPerRow);

    constexpr sampler s_atlas(filter::linear, address::clamp_to_edge);
    float alpha = glyphAtlas.sample(s_atlas, float2(atlasU, atlasV)).r;

    // Step 4: flat green for now. Trail fade and head highlight in Step 5.
    return float4(0.0, 1.0, 0.4, 1.0) * alpha;
}
