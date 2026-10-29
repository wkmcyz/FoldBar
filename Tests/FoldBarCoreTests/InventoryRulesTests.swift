import XCTest
import CoreGraphics
@testable import FoldBarCore

final class InventoryRulesTests: XCTestCase {
    private let band = CGRect(x: 0, y: 0, width: 1800, height: 43)

    func testEnabledButFoldedItemIsRetained() {
        XCTAssertTrue(InventoryRules.isEnabledMenuItem(onScreen: false, evidence: .active,
                                                      previouslyActive: false, displacedByFoldBar: true))
        XCTAssertTrue(InventoryRules.isEnabledMenuItem(onScreen: false, evidence: .active,
                                                      previouslyActive: false, displacedByFoldBar: false))
    }

    func testDisabledItemIsExcludedEvenIfPreviouslyFolded() {
        XCTAssertFalse(InventoryRules.isEnabledMenuItem(onScreen: false, evidence: .inactive,
                                                       previouslyActive: false, displacedByFoldBar: false))
        XCTAssertFalse(InventoryRules.isEnabledMenuItem(onScreen: false, evidence: .inactive,
                                                       previouslyActive: true, displacedByFoldBar: true))
    }

    func testUnreadableOwnerCannotIntroduceUnseenWindows() {
        XCTAssertFalse(InventoryRules.isEnabledMenuItem(onScreen: false, evidence: .unavailable,
                                                       previouslyActive: false, displacedByFoldBar: true))
        XCTAssertFalse(InventoryRules.isEnabledMenuItem(onScreen: false, evidence: .unavailable,
                                                       previouslyActive: true, displacedByFoldBar: false))
        XCTAssertTrue(InventoryRules.isEnabledMenuItem(onScreen: false, evidence: .unavailable,
                                                      previouslyActive: true, displacedByFoldBar: true))
        XCTAssertTrue(InventoryRules.isEnabledMenuItem(onScreen: true, evidence: .unavailable,
                                                      previouslyActive: false, displacedByFoldBar: false))
    }

    func testAXButtonMatchesWindowPaddingAndOffscreenCoordinates() {
        XCTAssertTrue(InventoryRules.matchesMenuExtra(window: CGRect(x: 1660, y: 0, width: 142, height: 43),
                                                      extra: CGRect(x: 1668, y: 10.5, width: 126, height: 22)))
        XCTAssertTrue(InventoryRules.matchesMenuExtra(window: CGRect(x: -2470, y: 0, width: 32, height: 43),
                                                      extra: CGRect(x: -2462, y: 10.5, width: 16, height: 22)))
        XCTAssertFalse(InventoryRules.matchesMenuExtra(window: CGRect(x: 1513, y: 0, width: 33, height: 43),
                                                       extra: CGRect(x: 1554, y: 10.5, width: 26, height: 22)))
    }

    func testEnumerationKeepsWindowsFarOutsideScreen() {
        XCTAssertTrue(InventoryRules.isStatusItem(frame: CGRect(x: -7500, y: 0, width: 38, height: 43),
                                                 layer: 25, statusLayer: 25, menuBands: [band]))
        XCTAssertTrue(InventoryRules.isStatusItem(frame: CGRect(x: 900, y: 0, width: 38, height: 43),
                                                 layer: 25, statusLayer: 25, menuBands: [band]))
    }

    func testRejectsPopoversOldHeightCopiesAndNonStatusWindows() {
        for frame in [CGRect(x: 1100, y: 31, width: 296, height: 164),
                      CGRect(x: 850, y: 0, width: 38, height: 24),
                      CGRect(x: -2000, y: 0, width: 3600, height: 43)] {
            XCTAssertFalse(InventoryRules.isStatusItem(frame: frame, layer: 25, statusLayer: 25, menuBands: [band]))
        }
        XCTAssertFalse(InventoryRules.isStatusItem(frame: CGRect(x: 100, y: 0, width: 38, height: 43),
                                                  layer: 24, statusLayer: 25, menuBands: [band]))
    }

    func testClassificationWorksWithExpandedAndOversizedDividers() {
        let divider = CGRect(x: -2000, y: 0, width: 3600, height: 43)
        let archive = CGRect(x: -5660, y: 0, width: 3600, height: 43)
        XCTAssertEqual(InventoryRules.group(of: CGRect(x: -5700, y: 0, width: 38, height: 43), divider: divider, archive: archive), .archive)
        XCTAssertEqual(InventoryRules.group(of: CGRect(x: -2040, y: 0, width: 38, height: 43), divider: divider, archive: archive), .hidden)
        XCTAssertEqual(InventoryRules.group(of: CGRect(x: 1650, y: 0, width: 38, height: 43), divider: divider, archive: archive), .visible)
    }

    func testMoveMustReachRequestedSideNotJustChangeCoordinates() {
        let control = CGRect(x: 1500, y: 0, width: 40, height: 43)
        let divider = CGRect(x: 1400, y: 0, width: 38, height: 43)
        let archive = CGRect(x: 1200, y: 0, width: 38, height: 43)
        let wrong = CGRect(x: 1300, y: 0, width: 38, height: 43)
        XCTAssertFalse(InventoryRules.hasReached(.visible, item: wrong, control: control, divider: divider, archive: archive))
        XCTAssertTrue(InventoryRules.hasReached(.hidden, item: wrong, control: control, divider: divider, archive: archive))
        XCTAssertFalse(InventoryRules.hasReached(.archive, item: wrong, control: control, divider: divider, archive: archive))
        XCTAssertFalse(InventoryRules.hasReached(.archive, item: wrong, control: control, divider: divider, archive: nil))
    }
}
