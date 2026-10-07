import CoreGraphics
import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct DragTrackerTests {
    @Test func plainClickDoesNothing() {
        var tracker = DragTracker()
        tracker.begin(mouse: CGPoint(x: 10, y: 10), origin: CGPoint(x: 100, y: 100), interruptedAnimation: false)
        #expect(tracker.end(at: 1.0) == DragTracker.Release.none)
    }

    /// 吸着アニメーション中に掴んで動かさずに離したら、途中で止めたままにせず吸着し直す
    @Test func clickThatInterruptedAnimationSettlesFromRest() {
        var tracker = DragTracker()
        tracker.begin(mouse: CGPoint(x: 10, y: 10), origin: CGPoint(x: 100, y: 100), interruptedAnimation: true)
        #expect(tracker.end(at: 1.0) == .settle(velocity: .zero))
    }

    @Test func movementBelowThresholdIsNotADrag() {
        var tracker = DragTracker()
        tracker.begin(mouse: CGPoint(x: 10, y: 10), origin: CGPoint(x: 100, y: 100), interruptedAnimation: false)
        #expect(tracker.move(mouse: CGPoint(x: 12, y: 11), at: 0.05) == nil)
        #expect(tracker.end(at: 0.1) == DragTracker.Release.none)
    }

    @Test func dragMovesOriginOneToOne() {
        var tracker = DragTracker()
        tracker.begin(mouse: CGPoint(x: 10, y: 10), origin: CGPoint(x: 100, y: 100), interruptedAnimation: false)
        #expect(tracker.move(mouse: CGPoint(x: 40, y: -10), at: 0.05) == CGPoint(x: 130, y: 80))
    }

    @Test func releaseVelocityUsesRecentSamples() {
        var tracker = DragTracker()
        tracker.begin(mouse: .zero, origin: .zero, interruptedAnimation: false)
        _ = tracker.move(mouse: CGPoint(x: 10, y: 0), at: 1.00)
        _ = tracker.move(mouse: CGPoint(x: 60, y: 0), at: 1.05)
        guard case let .settle(velocity) = tracker.end(at: 1.06) else {
            Issue.record("expected settle")
            return
        }
        #expect(abs(velocity.dx - 1_000) < 0.001)
        #expect(velocity.dy == 0)
    }

    @Test func stoppingBeforeReleaseGivesZeroVelocity() {
        var tracker = DragTracker()
        tracker.begin(mouse: .zero, origin: .zero, interruptedAnimation: false)
        _ = tracker.move(mouse: CGPoint(x: 10, y: 0), at: 1.00)
        _ = tracker.move(mouse: CGPoint(x: 60, y: 0), at: 1.05)
        #expect(tracker.end(at: 1.5) == .settle(velocity: .zero))
    }

    @Test func endWithoutBeginIsIgnored() {
        var tracker = DragTracker()
        #expect(tracker.end(at: 1) == DragTracker.Release.none)
        #expect(tracker.move(mouse: CGPoint(x: 50, y: 50), at: 1) == nil)
    }
}
