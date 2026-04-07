import XCTest
@testable import SciPlotGodMac

final class InspectorLayoutPolicyTests: XCTestCase {
    func testUnifiedInspectorColumnWidthPolicyStaysStable() {
        XCTAssertEqual(InspectorColumnLayoutPolicy.minWidth, 360)
        XCTAssertEqual(InspectorColumnLayoutPolicy.idealWidth, 400)
        XCTAssertEqual(InspectorColumnLayoutPolicy.maxWidth, 460)
        XCTAssertLessThan(InspectorColumnLayoutPolicy.minWidth, InspectorColumnLayoutPolicy.idealWidth)
        XCTAssertLessThan(InspectorColumnLayoutPolicy.idealWidth, InspectorColumnLayoutPolicy.maxWidth)
    }
}
