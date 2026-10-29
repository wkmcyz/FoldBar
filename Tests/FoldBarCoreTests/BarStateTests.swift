import XCTest
@testable import FoldBarCore

final class BarStateTests: XCTestCase {
    func testFirstLaunchNeverHidesUnarrangedIcons() {
        let state = BarState(archiveEnabled: true)
        XCTAssertEqual(state.mode, .organizing)
        XCTAssertFalse(state.archiveIsHidden)
        XCTAssertFalse(state.mayAutoHide(enabled: true, interacting: false))
    }

    func testRegularToggleDoesNotRevealArchive() {
        var state = BarState(archiveEnabled: true)
        state.toggle()
        XCTAssertEqual(state.mode, .collapsed)
        state.toggle()
        XCTAssertEqual(state.mode, .expanded)
        XCTAssertTrue(state.archiveIsHidden)
        state.setMode(.organizing)
        XCTAssertFalse(state.archiveIsHidden)
    }

    func testDisabledArchiveAlwaysRemainsRevealed() {
        var state = BarState()
        for mode in [BarMode.collapsed, .expanded, .organizing] {
            state.setMode(mode)
            XCTAssertFalse(state.archiveIsHidden)
        }
    }

    func testAutoHideOnlyWhenExpandedAndIdle() {
        var state = BarState()
        for mode in [BarMode.collapsed, .expanded, .organizing] {
            state.setMode(mode)
            for enabled in [false, true] {
                for interacting in [false, true] {
                    XCTAssertEqual(state.mayAutoHide(enabled: enabled, interacting: interacting),
                                   mode == .expanded && enabled && !interacting)
                }
            }
        }
    }

    func testHideWidthCoversWidestDisplayRegardlessOfOrder() {
        XCTAssertEqual(BarGeometry.hidingWidth(screenWidths: [1440, 3840]), 7680)
        XCTAssertEqual(BarGeometry.hidingWidth(screenWidths: [3840, 1440]), 7680)
    }

    func testHideWidthIsBoundedAndIgnoresInvalidDisplays() {
        XCTAssertEqual(BarGeometry.hidingWidth(screenWidths: [10000]), 10000)
        XCTAssertEqual(BarGeometry.hidingWidth(screenWidths: [100]), 500)
        XCTAssertEqual(BarGeometry.hidingWidth(screenWidths: [.nan, -.infinity, -1]), 3840)
        XCTAssertEqual(BarGeometry.hidingWidth(screenWidths: []), 3840)
    }

    func testRejectsArrangementThatWouldHideControl() {
        XCTAssertFalse(BarGeometry.isOrdered(controlX: 100, dividerX: 200, archiveX: nil, archiveEnabled: false))
        XCTAssertFalse(BarGeometry.isOrdered(controlX: nil, dividerX: 100, archiveX: nil, archiveEnabled: false))
        XCTAssertFalse(BarGeometry.isOrdered(controlX: 200, dividerX: nil, archiveX: nil, archiveEnabled: false))
        XCTAssertTrue(BarGeometry.isOrdered(controlX: 200, dividerX: 100, archiveX: nil, archiveEnabled: false))
    }

    func testArchiveMustBeLeftOfRegularGroup() {
        XCTAssertFalse(BarGeometry.isOrdered(controlX: 300, dividerX: 100, archiveX: 200, archiveEnabled: true))
        XCTAssertFalse(BarGeometry.isOrdered(controlX: 300, dividerX: 200, archiveX: nil, archiveEnabled: true))
        XCTAssertTrue(BarGeometry.isOrdered(controlX: 300, dividerX: 200, archiveX: 100, archiveEnabled: true))
    }

    func testItemsInsideDisplayButBehindNotchAreNotVisible() {
        // Actual geometry from the affected 1800 x 1169 display. The old screen-center check incorrectly passed these.
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let areas = [CGRect(x: 0, y: 1131, width: 790, height: 38), CGRect(x: 1010, y: 1131, width: 790, height: 38)]
        XCTAssertFalse(BarGeometry.isVisible(frame: CGRect(x: 869, y: 1126, width: 38, height: 43), screen: screen, menuBarAreas: areas))
        XCTAssertFalse(BarGeometry.isVisible(frame: CGRect(x: 985, y: 1126, width: 46, height: 43), screen: screen, menuBarAreas: areas))
        XCTAssertTrue(BarGeometry.isVisible(frame: CGRect(x: 1100, y: 1126, width: 38, height: 43), screen: screen, menuBarAreas: areas))
    }

    func testOffscreenAndPartlyClippedItemsAreNotVisible() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let area = CGRect(x: 0, y: 1120, width: 1800, height: 49)
        XCTAssertFalse(BarGeometry.isVisible(frame: CGRect(x: -10, y: 1126, width: 38, height: 43), screen: screen, menuBarAreas: [area]))
        XCTAssertFalse(BarGeometry.isVisible(frame: CGRect(x: -2631, y: 1126, width: 3616, height: 43), screen: screen, menuBarAreas: [area]))
        XCTAssertFalse(BarGeometry.isVisible(frame: CGRect(x: 300, y: 800, width: 38, height: 43), screen: screen, menuBarAreas: [area]))
    }

    func testVisibilityOnDisplayWithNegativeCoordinates() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let area = CGRect(x: -1920, y: 1050, width: 1920, height: 30)
        XCTAssertTrue(BarGeometry.isVisible(frame: CGRect(x: -300, y: 1053, width: 38, height: 27), screen: screen, menuBarAreas: [area]))
    }
}
