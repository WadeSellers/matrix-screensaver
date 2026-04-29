import Foundation
import simd

public struct ColumnState {
    public var headRow: Float
    public var speed: Float
    public var frameCounter: UInt32
    public var seed: UInt32

    public init(headRow: Float = 0,
                speed: Float = 15,
                frameCounter: UInt32 = 0,
                seed: UInt32 = 0) {
        self.headRow = headRow
        self.speed = speed
        self.frameCounter = frameCounter
        self.seed = seed
    }
}

public struct GridUniforms {
    public var columnCount: UInt32
    public var rowCount: UInt32
    public var cellSize: Float
    public var aspectFix: Float
    public var viewportSize: SIMD2<Float>

    public init(columnCount: UInt32,
                rowCount: UInt32,
                cellSize: Float,
                aspectFix: Float,
                viewportSize: SIMD2<Float>) {
        self.columnCount = columnCount
        self.rowCount = rowCount
        self.cellSize = cellSize
        self.aspectFix = aspectFix
        self.viewportSize = viewportSize
    }
}
