import CoreGraphics
import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct CounterRateTests {
    @Test func firstSampleIsZero() {
        var rate = CounterRate()
        #expect(rate.update(value: 1_000, at: 10) == 0)
    }

    @Test func computesBytesPerSecond() {
        var rate = CounterRate()
        _ = rate.update(value: 1_000, at: 10)
        #expect(rate.update(value: 3_000, at: 12) == 1_000)
    }

    @Test func counterDecreaseYieldsZeroAndRebases() {
        var rate = CounterRate()
        _ = rate.update(value: 5_000, at: 1)
        #expect(rate.update(value: 100, at: 2) == 0)
        #expect(rate.update(value: 600, at: 3) == 500)
    }

    @Test func nonPositiveElapsedYieldsZero() {
        var rate = CounterRate()
        _ = rate.update(value: 100, at: 5)
        #expect(rate.update(value: 200, at: 5) == 0)
        #expect(rate.update(value: 300, at: 4) == 0)
    }

    @Test func resetMakesNextSampleABaseline() {
        var rate = CounterRate()
        _ = rate.update(value: 100, at: 1)
        rate.reset()
        #expect(rate.update(value: 10_000, at: 2) == 0)
    }
}

@Suite struct CPUUsageTests {
    @Test func firstSampleIsNil() {
        var calc = CPUUsageCalculator()
        #expect(calc.update(CPUTicks(user: 10, system: 10, idle: 10, nice: 0)) == nil)
    }

    @Test func busyOverTotal() {
        var calc = CPUUsageCalculator()
        _ = calc.update(CPUTicks(user: 100, system: 50, idle: 850, nice: 0))
        let usage = calc.update(CPUTicks(user: 130, system: 60, idle: 900, nice: 10))
        // busy = 30 + 10 + 10 = 50, idle = 50 → 0.5
        #expect(usage == 0.5)
    }

    @Test func noElapsedTicksIsZero() {
        var calc = CPUUsageCalculator()
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        _ = calc.update(ticks)
        #expect(calc.update(ticks) == 0)
    }

    @Test func wrappedCounterIsNil() {
        var calc = CPUUsageCalculator()
        _ = calc.update(CPUTicks(user: 100, system: 100, idle: 100, nice: 0))
        #expect(calc.update(CPUTicks(user: 5, system: 200, idle: 200, nice: 0)) == nil)
    }

    @Test func alwaysWithinUnitRange() {
        var calc = CPUUsageCalculator()
        _ = calc.update(CPUTicks(user: 0, system: 0, idle: 0, nice: 0))
        let usage = calc.update(CPUTicks(user: 1_000, system: 0, idle: 0, nice: 0))
        #expect(usage == 1)
    }
}

@Suite struct SpringTests {
    @Test func convergesToTargetWithoutOvershoot() {
        var spring = CriticalSpring(position: 0, target: 100, response: 0.35)
        var maxPosition = 0.0
        for _ in 0..<120 {
            spring.step(dt: 1.0 / 60)
            maxPosition = max(maxPosition, spring.position)
        }
        #expect(spring.isSettled)
        #expect(abs(spring.position - 100) < 0.5)
        #expect(maxPosition <= 100.0001)
    }

    @Test func inheritsInitialVelocity() {
        var spring = CriticalSpring(position: 0, velocity: 2_000, target: 0, response: 0.35)
        spring.step(dt: 1.0 / 60)
        #expect(spring.position > 0)
    }

    @Test func largeStepDoesNotExplode() {
        var spring = CriticalSpring(position: 0, velocity: 5_000, target: 100, response: 0.35)
        spring.step(dt: 10)
        #expect(abs(spring.position - 100) < 0.5)
        #expect(spring.isSettled)
    }

    @Test func zeroStepIsNoop() {
        var spring = CriticalSpring(position: 3, velocity: 4, target: 10)
        spring.step(dt: 0)
        #expect(spring.position == 3)
        #expect(spring.velocity == 4)
    }
}

@Suite struct EdgeSnapTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func snapsToNearLeftAndTopEdges() {
        let frame = CGRect(x: 10, y: 800 - 300 - 20, width: 320, height: 300)
        let target = EdgeSnap.target(for: frame, in: screen)
        #expect(target == CGPoint(x: 16, y: 800 - 300 - 16))
    }

    @Test func snapsToNearRightEdge() {
        let frame = CGRect(x: 1000 - 320 - 5, y: 300, width: 320, height: 300)
        #expect(EdgeSnap.target(for: frame, in: screen).x == CGFloat(1000 - 320 - 16))
    }

    @Test func keepsPositionAwayFromEdges() {
        let frame = CGRect(x: 300, y: 250, width: 320, height: 300)
        #expect(EdgeSnap.target(for: frame, in: screen) == CGPoint(x: 300, y: 250))
    }

    @Test func clampsOffscreenFrameBackOntoScreen() {
        let frame = CGRect(x: 5_000, y: -2_000, width: 320, height: 300)
        let target = EdgeSnap.target(for: frame, in: screen)
        #expect(target == CGPoint(x: 1000 - 320 - 16, y: 16))
    }

    @Test func screenWithNonZeroOrigin() {
        let second = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -1430, y: 400, width: 320, height: 300)
        #expect(EdgeSnap.target(for: frame, in: second).x == CGFloat(-1440 + 16))
    }

    @Test func projectionMatchesAppleFormula() {
        // 1000pt/s, rate 0.998 → 1 * 0.998 / 0.002 = 499
        #expect(abs(EdgeSnap.project(velocity: 1_000) - 499) < 0.001)
        #expect(EdgeSnap.project(velocity: 0) == 0)
    }
}
