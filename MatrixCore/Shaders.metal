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
};

vertex VSOut vertex_fullscreen(uint vid [[vertex_id]]) {
    // Fullscreen-triangle trick: 3 verts cover the whole NDC.
    float2 pos = float2((vid << 1) & 2, vid & 2);
    VSOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = pos; // 0..1, origin bottom-left
    return out;
}

fragment float4 fragment_columns(
    VSOut in [[stage_in]],
    constant GridUniforms &grid [[buffer(0)]],
    constant ColumnState *columns [[buffer(1)]]
) {
    // Flip Y so row 0 is the top of the screen.
    float pixelX = in.uv.x * grid.viewportSize.x;
    float pixelY = (1.0 - in.uv.y) * grid.viewportSize.y;

    uint col = uint(pixelX / grid.cellSize);
    uint row = uint(pixelY / grid.cellSize);

    if (col >= grid.columnCount || row >= grid.rowCount) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    ColumnState s = columns[col];

    // Step 3: solid green where the row has been "passed" by the head.
    // Step 5 will replace this with a head highlight + trail-fade gradient.
    if (float(row) <= s.headRow) {
        return float4(0.0, 1.0, 0.4, 1.0);
    }
    return float4(0.0, 0.0, 0.0, 1.0);
}
