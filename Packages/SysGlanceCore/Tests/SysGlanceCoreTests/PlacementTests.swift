import CoreGraphics
import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct PanelPlacementTests {
    let main = CGRect(x: 0, y: 66, width: 1470, height: 857)
    let size = CGSize(width: 364, height: 382)

    @Test func noSavedOriginUsesTopRightOfMainScreen() {
        let origin = PanelPlacement.restoredOrigin(saved: nil, size: size, screens: [main], main: main)
        #expect(origin == CGPoint(x: 1470 - 364 - 16, y: 66 + 857 - 382 - 16))
    }

    @Test func fullyVisibleSavedOriginIsKept() {
        let saved = CGPoint(x: 300, y: 200)
        #expect(PanelPlacement.restoredOrigin(saved: saved, size: size, screens: [main], main: main) == saved)
    }

    @Test func sliverOverlapFallsBackToDefault() {
        // 1pt だけ画面に掛かっている位置（ディスプレイ構成変更後など）は掴めないので既定位置へ
        let saved = CGPoint(x: 1469, y: 300)
        let origin = PanelPlacement.restoredOrigin(saved: saved, size: size, screens: [main], main: main)
        #expect(origin == CGPoint(x: 1470 - 364 - 16, y: 66 + 857 - 382 - 16))
    }

    @Test func mostlyVisibleSavedOriginIsPulledInside() {
        let saved = CGPoint(x: 1470 - 200, y: 300)  // 幅の約55%が画面内
        let origin = PanelPlacement.restoredOrigin(saved: saved, size: size, screens: [main], main: main)
        #expect(origin == CGPoint(x: 1470 - 364 - 16, y: 300))
    }

    @Test func savedOriginOnSecondaryScreenIsKept() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let saved = CGPoint(x: -1000, y: 300)
        let origin = PanelPlacement.restoredOrigin(saved: saved, size: size, screens: [main, left], main: main)
        #expect(origin == saved)
    }

    @Test func fullyOffscreenFallsBackToDefault() {
        let origin = PanelPlacement.restoredOrigin(saved: CGPoint(x: 99_999, y: 99_999), size: size,
                                                   screens: [main], main: main)
        #expect(origin == CGPoint(x: 1470 - 364 - 16, y: 66 + 857 - 382 - 16))
    }
}
