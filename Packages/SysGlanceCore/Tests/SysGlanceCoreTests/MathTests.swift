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
