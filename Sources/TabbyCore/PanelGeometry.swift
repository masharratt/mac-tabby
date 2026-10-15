import CoreGraphics
import Foundation

extension ThumbnailSize {
    /// Bounding box (points) a thumbnail is fitted into.
    public var box: CGSize {
        switch self {
        case .small: CGSize(width: 150, height: 94)
        case .medium: CGSize(width: 210, height: 131)
        case .large: CGSize(width: 280, height: 175)
        }
    }

    /// Pixel size to request from the capture API for `scale` pixels per point.
    public func capturePixels(scale: CGFloat) -> CGSize {
        CGSize(width: box.width * scale, height: box.height * scale)
    }
}

/// Where items sit in the switcher panel. Rows are counted from the top.
public struct GridLayout: Equatable, Sendable {
    public var columns: Int
    public var totalRows: Int
    /// Rows actually drawn; all of them unless the screen cap forces scrolling.
    public var visibleRows: Range<Int>
    public var cellSize: CGSize
    public var spacing: CGFloat
    public var padding: CGFloat
    public var panelSize: CGSize
    /// Item indices drawn (row-major).
    public var itemRange: Range<Int>

    /// Row (relative to the first visible row) and column of an item, nil when not drawn.
    public func slot(of index: Int) -> (row: Int, column: Int)? {
        guard itemRange.contains(index), columns > 0 else { return nil }
        return (index / columns - visibleRows.lowerBound, index % columns)
    }

    /// Top-left of a slot's cell, measured from the panel's top-left corner.
    public func origin(row: Int, column: Int) -> CGPoint {
        CGPoint(x: padding + CGFloat(column) * (cellSize.width + spacing),
                y: padding + CGFloat(row) * (cellSize.height + spacing))
    }
}

/// Pure layout math for the switcher panel: cell sizes, wrapping, the 90% screen cap.
public enum PanelGeometry {
    public static let screenFraction: CGFloat = 0.9
    public static let titlesMaxWidth: CGFloat = 640
    static let titleRowHeight: CGFloat = 32
    static let iconCell = CGSize(width: 112, height: 112)
    /// App Icons with window titles: wider for the text, taller for a second title line.
    static let iconCellWithTitles = CGSize(width: 140, height: 132)
    static let thumbInset: CGFloat = 8
    static let thumbLabelHeight: CGFloat = 26

    static func padding(_ layout: Layout) -> CGFloat { 12 }
    static func spacing(_ layout: Layout) -> CGFloat { layout == .titles ? 2 : 10 }

    public static func cellSize(layout: Layout, thumbnailSize: ThumbnailSize, screenWidth: CGFloat,
                                showWindowTitles: Bool = true) -> CGSize {
        switch layout {
        case .titles:
            let width = min(titlesMaxWidth, screenWidth * screenFraction) - 2 * padding(layout)
            return CGSize(width: max(width, 1), height: titleRowHeight)
        case .appIcons:
            return showWindowTitles ? iconCellWithTitles : iconCell
        case .thumbnails:
            let b = thumbnailSize.box
            return CGSize(width: b.width + 2 * thumbInset, height: b.height + 2 * thumbInset + thumbLabelHeight)
        }
    }

    /// Most columns that fit in 90% of the screen width (at least 1; always 1 for titles).
    public static func maxColumns(layout: Layout, thumbnailSize: ThumbnailSize, screenWidth: CGFloat,
                                  showWindowTitles: Bool = true) -> Int {
        if layout == .titles { return 1 }
        let cell = cellSize(layout: layout, thumbnailSize: thumbnailSize, screenWidth: screenWidth,
                            showWindowTitles: showWindowTitles)
        let room = screenWidth * screenFraction - 2 * padding(layout)
        return max(1, Int(((room + spacing(layout)) / (cell.width + spacing(layout))).rounded(.down)))
    }

    public static func grid(count: Int, selected: Int, layout: Layout, thumbnailSize: ThumbnailSize,
                            screen: CGSize, showWindowTitles: Bool = true) -> GridLayout {
        let pad = padding(layout), gap = spacing(layout)
        let cell = cellSize(layout: layout, thumbnailSize: thumbnailSize, screenWidth: screen.width,
                            showWindowTitles: showWindowTitles)
        guard count > 0 else {
            return GridLayout(columns: 0, totalRows: 0, visibleRows: 0..<0, cellSize: cell, spacing: gap,
                              padding: pad, panelSize: .zero, itemRange: 0..<0)
        }
        let maxCols = maxColumns(layout: layout, thumbnailSize: thumbnailSize, screenWidth: screen.width,
                               showWindowTitles: showWindowTitles)
        let rows = (count + maxCols - 1) / maxCols
        let columns = (count + rows - 1) / rows   // balanced: 10 items, 8 max -> 2 rows of 5
        let roomH = screen.height * screenFraction - 2 * pad
        let capacity = max(1, Int(((roomH + gap) / (cell.height + gap)).rounded(.down)))
        let sel = min(max(selected, 0), count - 1)
        let visible = SelectionIndex.visibleRange(count: rows, selected: sel / columns, capacity: capacity)
        let shownRows = visible.count
        let size = CGSize(
            width: CGFloat(columns) * cell.width + CGFloat(columns - 1) * gap + 2 * pad,
            height: CGFloat(shownRows) * cell.height + CGFloat(shownRows - 1) * gap + 2 * pad
        )
        let items = (visible.lowerBound * columns)..<min(count, visible.upperBound * columns)
        return GridLayout(columns: columns, totalRows: rows, visibleRows: visible, cellSize: cell, spacing: gap,
                          padding: pad, panelSize: size, itemRange: items)
    }

    /// Largest size with `content`'s aspect ratio that fits `box`; never upscales.
    /// Unknown (zero) content gives the box.
    public static func fit(_ content: CGSize, in box: CGSize) -> CGSize {
        guard content.width > 0, content.height > 0 else { return box }
        let k = min(1, box.width / content.width, box.height / content.height)
        return CGSize(width: (content.width * k).rounded(), height: (content.height * k).rounded())
    }
}
