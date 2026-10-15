import XCTest
import AppKit
@testable import VoiceType

final class HUDControllerTests: XCTestCase {

    @MainActor
    func testShowCreatesPanelWithExpectedConfiguration() {
        let controller = HUDController()
        controller.style = .pill
        controller.show(state: .processing)
        defer { controller.hide() }

        let panel = controller.panelForTesting
        XCTAssertNotNil(panel)
        guard let panel else { return }

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
    }

    @MainActor
    func testHideReleasesPanel() {
        let controller = HUDController()
        controller.style = .pill
        controller.show(state: .processing)
        XCTAssertNotNil(controller.panelForTesting)
        controller.hide()
        XCTAssertNil(controller.panelForTesting)
    }

    @MainActor
    func testPositionsBottomCenterOfActiveScreen() {
        let controller = HUDController()
        controller.style = .pill
        controller.show(state: .processing)
        defer { controller.hide() }
        guard let panel = controller.panelForTesting,
              let screen = NSScreen.main else {
            return XCTFail("No screen / panel")
        }
        let frame = panel.frame
        let visible = screen.visibleFrame
        let expectedX = visible.midX - frame.width / 2
        XCTAssertEqual(frame.origin.x, expectedX, accuracy: 2)
        XCTAssertEqual(frame.origin.y, visible.minY + 120, accuracy: 2)
    }
}
