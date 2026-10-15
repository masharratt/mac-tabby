import CoreGraphics
import Testing
@testable import TabbyCore

@Suite struct PanelGeometryTests {
    let screen = CGSize(width: 1920, height: 1080)

    func grid(_ n: Int, _ layout: Layout = .thumbnails, size: ThumbnailSize = .medium,
              selected: Int = 0, screen: CGSize? = nil) -> GridLayout {
        PanelGeometry.grid(count: n, selected: selected, layout: layout, thumbnailSize: size, screen: screen ?? self.screen)
    }

    @Test func emptyListHasNoSize() {
        let g = grid(0)
        #expect(g.columns == 0 && g.panelSize == .zero && g.itemRange.isEmpty)
    }

    @Test func fewItemsFitOneRow() {
        let g = grid(3)
        let expected = 3 * g.cellSize.width + 2 * g.spacing + 2 * g.padding
        #expect(g.columns == 3 && g.totalRows == 1)
        #expect(abs(g.panelSize.width - expected) < 0.001, "width=\(g.panelSize.width) expected=\(expected)")
        #expect(g.itemRange == 0..<3)
    }

    @Test func manyItemsWrapWithinNinetyPercentOfWidth() {
        let narrow = CGSize(width: 1000, height: 1000)
        let g = grid(20, screen: narrow)
        #expect(g.totalRows > 1)
        #expect(g.panelSize.width <= narrow.width * 0.9 + 0.001, "width=\(g.panelSize.width)")
        #expect(g.columns * g.totalRows >= 20)
    }

    @Test func rowsAreBalanced() {
        // 10 items with room for 8 columns: 2 rows of 5, not 8 + 2.
        let g = grid(10, size: .small, screen: CGSize(width: 1920, height: 1080))
        #expect(g.totalRows == Int((Double(10) / Double(g.columns)).rounded(.up)))
        let maxCols = PanelGeometry.maxColumns(layout: .thumbnails, thumbnailSize: .small, screenWidth: 1920)
        #expect(g.columns <= maxCols)
        if maxCols < 10 { #expect(g.columns == 5, "columns=\(g.columns) maxCols=\(maxCols)") }
    }

    @Test func heightIsCappedAndSelectionStaysVisible() {
        let g = grid(200, selected: 150, screen: CGSize(width: 1000, height: 700))
        #expect(g.panelSize.height <= 700 * 0.9 + 0.001, "height=\(g.panelSize.height)")
        #expect(g.itemRange.contains(150), "range=\(g.itemRange)")
        #expect(g.visibleRows.count < g.totalRows)
    }

    @Test func selectionNearStartShowsFirstRows() {
        let g = grid(200, selected: 0, screen: CGSize(width: 1000, height: 700))
        #expect(g.visibleRows.lowerBound == 0)
        #expect(g.itemRange.lowerBound == 0)
    }

    @Test func lastRowMayBeShort() {
        let g = grid(7, size: .large, selected: 6, screen: CGSize(width: 1000, height: 1000))
        #expect(g.itemRange.upperBound == 7)
    }

    @Test func titlesLayoutIsOneColumnAtMost640Wide() {
        let g = grid(5, .titles)
        #expect(g.columns == 1 && g.totalRows == 5)
        #expect(g.panelSize.width <= 640 + 0.001)
        #expect(g.cellSize.height == 32)
    }

    @Test func tinyScreenStillShowsOneCell() {
        let g = grid(5, screen: CGSize(width: 100, height: 100))
        #expect(g.columns >= 1 && g.visibleRows.count >= 1)
        #expect(g.itemRange.contains(0))
    }

    @Test func largerThumbnailSizeMeansBiggerCells() {
        let s = grid(1, size: .small).cellSize, l = grid(1, size: .large).cellSize
        #expect(l.width > s.width && l.height > s.height)
    }

    @Test func iconsLayoutCellsAreSmallerThanThumbnails() {
        #expect(grid(1, .appIcons).cellSize.width < grid(1, .thumbnails, size: .small).cellSize.width)
    }

    @Test func slotMapsIndexToRowAndColumn() {
        let g = grid(10, size: .small, screen: CGSize(width: 1000, height: 1080))
        let slot = g.slot(of: g.columns + 1)
        #expect(slot?.row == 1 && slot?.column == 1)
        #expect(g.slot(of: 999) == nil)
    }

    @Test func fitKeepsAspectAndNeverUpscales() {
        let box = CGSize(width: 200, height: 100)
        #expect(PanelGeometry.fit(CGSize(width: 800, height: 400), in: box) == CGSize(width: 200, height: 100))
        #expect(PanelGeometry.fit(CGSize(width: 400, height: 800), in: box) == CGSize(width: 50, height: 100))
        #expect(PanelGeometry.fit(CGSize(width: 100, height: 50), in: box) == CGSize(width: 100, height: 50))
        #expect(PanelGeometry.fit(.zero, in: box) == box)
    }

    @Test func capturePixelSizeScalesTheBox() {
        let px = ThumbnailSize.medium.capturePixels(scale: 2)
        #expect(px.width == ThumbnailSize.medium.box.width * 2)
    }
}
