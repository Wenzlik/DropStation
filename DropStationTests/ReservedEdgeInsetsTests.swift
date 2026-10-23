import XCTest
import CoreGraphics
@testable import DropStation

/// The pure rule behind `avoidsReservedRegions()` — runs without a
/// hinged device.
final class ReservedEdgeInsetsTests: XCTestCase {
    private let size = CGSize(width: 600, height: 900)

    func testNoRegionsNoInsets() {
        XCTAssertEqual(ReservedEdgeInsets(avoiding: [], in: size), ReservedEdgeInsets())
    }

    func testSideColumnPadsThatEdge() {
        let trailing = ReservedEdgeInsets(avoiding: [CGRect(x: 560, y: 0, width: 40, height: 300)], in: size)
        XCTAssertEqual(trailing, ReservedEdgeInsets(trailing: 40))
        let leading = ReservedEdgeInsets(avoiding: [CGRect(x: 0, y: 100, width: 30, height: 200)], in: size)
        XCTAssertEqual(leading, ReservedEdgeInsets(leading: 30))
    }

    func testFoldKeepsContentOnTheLargerSide() {
        // Vertical fold left of centre: content keeps the trailing side.
        let offCentre = ReservedEdgeInsets(avoiding: [CGRect(x: 200, y: 0, width: 20, height: 900)], in: size)
        XCTAssertEqual(offCentre, ReservedEdgeInsets(leading: 220))
        // Centred fold: equal halves keep the leading one.
        let centred = ReservedEdgeInsets(avoiding: [CGRect(x: 290, y: 0, width: 20, height: 900)], in: size)
        XCTAssertEqual(centred, ReservedEdgeInsets(trailing: 310))
        // Tabletop: horizontal fold through the middle keeps the top half.
        let tabletop = ReservedEdgeInsets(avoiding: [CGRect(x: 0, y: 440, width: 600, height: 20)], in: size)
        XCTAssertEqual(tabletop, ReservedEdgeInsets(bottom: 460))
    }

    func testRegionsOutsideAreIgnored() {
        let outside = ReservedEdgeInsets(avoiding: [CGRect(x: 600, y: 0, width: 40, height: 900)], in: size)
        XCTAssertEqual(outside, ReservedEdgeInsets())
    }

    func testSafeAreaAlreadyCoveringItIsNotPaddedTwice() {
        let column = ReservedEdgeInsets(avoiding: [CGRect(x: 560, y: 0, width: 40, height: 300)], in: size)
        XCTAssertEqual(column.beyond(ReservedEdgeInsets(trailing: 44)), ReservedEdgeInsets())
        XCTAssertEqual(column.beyond(ReservedEdgeInsets(trailing: 10)), ReservedEdgeInsets(trailing: 30))
    }
}
