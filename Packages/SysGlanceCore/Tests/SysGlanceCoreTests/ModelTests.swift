import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct RingBufferTests {
    @Test func keepsInsertionOrderBelowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.elements == [1, 2])
        #expect(buffer.last == 2)
        #expect(buffer.count == 2)
    }

    @Test func dropsOldestWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { buffer.append(i) }
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.count == 3)
        #expect(buffer.last == 5)
    }

    @Test func suffixReturnsNewestInOldestFirstOrder() {
        var buffer = RingBuffer<Int>(capacity: 4)
        for i in 1...6 { buffer.append(i) }
        #expect(buffer.suffix(2) == [5, 6])
        #expect(buffer.suffix(10) == [3, 4, 5, 6])
    }

    @Test func emptyBuffer() {
        let buffer = RingBuffer<Int>(capacity: 2)
        #expect(buffer.isEmpty)
        #expect(buffer.last == nil)
        #expect(buffer.elements.isEmpty)
    }

    @Test func holdsThirtyMinutesAtOneHertz() {
        var buffer = RingBuffer<Int>(capacity: 1800)
        for i in 0..<2000 { buffer.append(i) }
        #expect(buffer.count == 1800)
        #expect(buffer.elements.first == 200)
    }
}

@Suite struct ThresholdTests {
    @Test func pressureFromSysctl() {
        #expect(MemoryPressure(sysctlValue: 1) == .normal)
        #expect(MemoryPressure(sysctlValue: 2) == .warning)
        #expect(MemoryPressure(sysctlValue: 4) == .critical)
        #expect(MemoryPressure(sysctlValue: 0) == .normal)
        #expect(Thresholds.level(for: MemoryPressure.critical) == .critical)
    }

    @Test func diskLevels() {
        #expect(Thresholds.level(for: DiskMetrics(total: 100, available: 50)) == .normal)
        #expect(Thresholds.level(for: DiskMetrics(total: 100, available: 10)) == .normal)
        #expect(Thresholds.level(for: DiskMetrics(total: 100, available: 9)) == .warning)
        #expect(Thresholds.level(for: DiskMetrics(total: 100, available: 4)) == .critical)
        #expect(Thresholds.level(for: DiskMetrics(total: 0, available: 0)) == .normal)
    }

    @Test func batteryLevelsIgnoreACPower() {
        #expect(Thresholds.level(for: BatteryMetrics(level: 0.15, isCharging: false, isOnAC: false, minutesRemaining: 30)) == .warning)
        #expect(Thresholds.level(for: BatteryMetrics(level: 0.05, isCharging: false, isOnAC: false, minutesRemaining: 5)) == .critical)
        #expect(Thresholds.level(for: BatteryMetrics(level: 0.05, isCharging: true, isOnAC: true, minutesRemaining: nil)) == .normal)
        #expect(Thresholds.level(for: BatteryMetrics(level: 0.5, isCharging: false, isOnAC: false, minutesRemaining: 120)) == .normal)
    }

    @Test func diskUsedNeverUnderflows() {
        #expect(DiskMetrics(total: 10, available: 20).used == 0)
    }
}
