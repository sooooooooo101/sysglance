import Foundation
import Testing
@testable import SysGlanceCore

/// 実機の OS API を叩くスモークテスト。値の正確さではなく「取れて、妥当な範囲にある」ことを確認する。
@Suite struct SystemSmokeTests {
    @Test func memoryIsPlausible() throws {
        let memory = try #require(HostReaders.memory())
        #expect(memory.total == ProcessInfo.processInfo.physicalMemory)
        #expect(memory.used > 0)
        #expect(memory.used <= memory.total)
    }

    @Test func cpuTicksAdvance() async throws {
        let first = try #require(HostReaders.cpuTicks())
        try await Task.sleep(for: .milliseconds(200))
        let second = try #require(HostReaders.cpuTicks())
        var calc = CPUUsageCalculator()
        _ = calc.update(first)
        let maybeUsage = calc.update(second)
        let usage = try #require(maybeUsage)
        #expect((0...1).contains(usage))
    }

    @Test func uptimeIsPositive() throws {
        let uptime = try #require(HostReaders.uptime())
        #expect(uptime > 0)
    }

    @Test func rootVolumeCapacity() throws {
        let disk = try #require(IOReaders.diskCapacity())
        #expect(disk.total > 0)
        #expect(disk.available <= disk.total)
    }

    @Test func internalDiskCountersExist() throws {
        let bytes = try #require(IOReaders.internalDiskBytes())
        #expect(bytes.inbound > 0)
    }

    @Test func networkCountersExist() {
        #expect(IOReaders.networkBytes() != nil)
    }

    @Test(arguments: [
        ("en0", false, true), ("en7", false, true), ("lo0", true, false), ("utun4", false, false),
        ("awdl0", false, false), ("llw0", false, false), ("bridge0", false, false),
        // 標準の IKEv2/L2TP VPN・インターネット共有・VM ネットワークも物理 IF と二重計上になる
        ("ipsec0", false, false), ("ppp0", false, false), ("ap1", false, false), ("vmenet0", false, false),
    ])
    func interfaceFilter(name: String, loopback: Bool, counted: Bool) {
        #expect(IOReaders.isCountedInterface(name: name, isLoopback: loopback) == counted)
    }

    @Test func batteryIsNilOrInRange() {
        if let battery = IOReaders.battery() {
            #expect((0...1).contains(battery.level))
        }
    }

    @Test func topProcessesSortedAndLimited() {
        let top = ProcessReader.topByMemory(limit: 5)
        #expect(!top.isEmpty)
        #expect(top.count <= 5)
        #expect(zip(top, top.dropFirst()).allSatisfy { $0.memory >= $1.memory })
    }

    @Test func topSortingIsDeterministic() {
        let list = [ProcessUsage(pid: 3, name: "c", memory: 5), ProcessUsage(pid: 1, name: "a", memory: 5),
                    ProcessUsage(pid: 2, name: "b", memory: 9)]
        #expect(ProcessReader.top(list, limit: 2).map(\.pid) == [2, 1])
        #expect(ProcessReader.top(list, limit: -1).isEmpty)
    }
}

@Suite struct SamplingEngineTests {
    @Test func firstSampleHasBaselinesSecondHasRates() async throws {
        let engine = SamplingEngine()
        let first = await engine.sample()
        #expect(first.cpu == nil)
        #expect(first.memory != nil)
        #expect(first.disk != nil)
        #expect(first.uptime != nil)
        #expect(first.network?.inbound == 0)
        #expect(!first.topProcesses.isEmpty)

        try await Task.sleep(for: .milliseconds(300))
        let second = await engine.sample()
        let cpu = try #require(second.cpu)
        #expect((0...1).contains(cpu.usage))
        #expect((second.network?.inbound ?? -1) >= 0)
    }

    @Test func resetBaselinesClearsCPU() async throws {
        let engine = SamplingEngine()
        _ = await engine.sample()
        try await Task.sleep(for: .milliseconds(100))
        await engine.resetBaselines()
        #expect(await engine.sample().cpu == nil)
    }

    @Test func processListRefreshesOnlyAfterInterval() async {
        let ticker = Ticker()
        let engine = SamplingEngine(processInterval: 5, processLimit: 3, clock: { ticker.now })
        let first = await engine.sample()
        ticker.now = 1
        let second = await engine.sample()
        #expect(first.topProcesses == second.topProcesses)
        #expect(first.topProcesses.count <= 3)
    }
}

final class Ticker: @unchecked Sendable {
    var now: TimeInterval = 0
}
