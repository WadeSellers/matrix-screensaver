import CoreGraphics

public struct GridLayout {
    public let cellSize: CGFloat
    public let columnCount: Int
    public let rowCount: Int
    public let viewportSize: CGSize

    public init(drawableSize: CGSize, targetRowCount: Int = 60) {
        let cell = max(1.0, floor(drawableSize.height / CGFloat(targetRowCount)))
        self.cellSize = cell
        self.columnCount = max(1, Int(floor(drawableSize.width / cell)))
        self.rowCount = max(1, Int(floor(drawableSize.height / cell)))
        self.viewportSize = drawableSize
    }
}
