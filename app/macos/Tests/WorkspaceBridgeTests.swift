import XCTest
@testable import SciPlotGodMac

@MainActor
final class WorkspaceBridgeTests: XCTestCase {
    func testOpenMissingURLThrowsFriendlyError() {
        let missingURL = URL(fileURLWithPath: "/tmp/workspace-bridge-missing.pdf")

        XCTAssertThrowsError(try WorkspaceBridge.open(missingURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Couldn't find"))
        }
    }

    func testRevealMissingURLThrowsFriendlyError() {
        let missingURL = URL(fileURLWithPath: "/tmp/workspace-bridge-missing-folder")

        XCTAssertThrowsError(try WorkspaceBridge.reveal([missingURL])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Couldn't find"))
        }
    }
}
