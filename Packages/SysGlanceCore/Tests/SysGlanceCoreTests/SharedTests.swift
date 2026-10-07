import Foundation
import Testing
@testable import SysGlanceCore

enum Fixtures {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    static let snapshot = MetricsSnapshot(
        date: date,
        cpu: CPUMetrics(usage: 0.42),
        memory: MemoryMetrics(total: 17_179_869_184, app: 4_000_000_000, wired: 3_000_000_000,
                              compressed: 2_000_000_000, cached: 5_000_000_000,
                              swapUsed: 1_073_741_824, swapTotal: 2_147_483_648, pressure: .warning),
        disk: DiskMetrics(total: 245_107_195_904, available: 25_592_918_572),
        diskIO: Throughput(inbound: 1_200_000, outbound: 0),
        network: Throughput(inbound: 1_500_000, outbound: 34_000),
        battery: BatteryMetrics(level: 0.88, isCharging: false, isOnAC: false, minutesRemaining: 250),
        uptime: 3 * 86400 + 14 * 3600,
        topProcesses: [
            ProcessUsage(pid: 10, name: "ChatGPT", memory: 2_285_000_000),
            ProcessUsage(pid: 11, name: "Xcode", memory: 1_858_000_000),
            ProcessUsage(pid: 12, name: "Safari", memory: 1_072_000_000),
            ProcessUsage(pid: 13, name: "Mail", memory: 300_000_000),
        ]
    )
}

@Suite struct SnapshotFileTests {
    @Test func roundTrip() throws {
        let data = try SnapshotFile.encode(Fixtures.snapshot, capturedAt: Fixtures.date)
        let envelope = try SnapshotFile.decode(data)
        #expect(envelope.snapshot == Fixtures.snapshot)
        #expect(envelope.capturedAt == Fixtures.date)
        #expect(envelope.schemaVersion == SnapshotFile.schemaVersion)
    }

    @Test func rejectsUnknownSchema() throws {
        let data = try SnapshotFile.encode(Fixtures.snapshot, capturedAt: Fixtures.date)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schemaVersion"] = 99
        let modified = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: SnapshotFile.DecodeError.unsupportedSchema(99)) {
            try SnapshotFile.decode(modified)
        }
    }

    @Test func readReturnsNilForMissingOrCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("snapshot.json")
        #expect(SnapshotFile.read(from: url) == nil)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(SnapshotFile.read(from: url) == nil)
    }

    @Test func writeThenRead() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("snapshot.json")
        try SnapshotFile.write(Fixtures.snapshot, capturedAt: Fixtures.date, to: url)
        #expect(SnapshotFile.read(from: url)?.snapshot == Fixtures.snapshot)
    }

    @Test func staleness() throws {
        let envelope = try SnapshotFile.decode(SnapshotFile.encode(Fixtures.snapshot, capturedAt: Fixtures.date))
        // OS がウィジェット再読込を間引いても、動作中の本体を「起動していない」と誤判定しない長さにする
        #expect(!SnapshotFile.isStale(envelope, now: Fixtures.date.addingTimeInterval(2_699)))
        #expect(SnapshotFile.isStale(envelope, now: Fixtures.date.addingTimeInterval(2_700)))
    }
}

@Suite struct WidgetReloadPolicyTests {
    let t0 = Date(timeIntervalSince1970: 0)

    @Test func firstCallReloads() {
        var policy = WidgetReloadPolicy()
        let reload = policy.shouldReload(now: t0, pressure: .normal)
        #expect(reload)
    }

    /// WidgetKit の1日あたり予算（目安 40〜70 回）に収まるよう 15 分間隔（最大 96 回/日）
    @Test func throttlesWithinFifteenMinutes() {
        var policy = WidgetReloadPolicy()
        _ = policy.shouldReload(now: t0, pressure: .normal)
        let early = policy.shouldReload(now: t0.addingTimeInterval(899), pressure: .normal)
        let due = policy.shouldReload(now: t0.addingTimeInterval(900), pressure: .normal)
        #expect(!early)
        #expect(due)
    }

    @Test func pressureChangeReloadsImmediately() {
        var policy = WidgetReloadPolicy()
        _ = policy.shouldReload(now: t0, pressure: .normal)
        let changed = policy.shouldReload(now: t0.addingTimeInterval(10), pressure: .critical)
        let same = policy.shouldReload(now: t0.addingTimeInterval(20), pressure: .critical)
        #expect(changed)
        #expect(!same)
    }

    @Test func missingPressureDoesNotCountAsChange() {
        var policy = WidgetReloadPolicy()
        _ = policy.shouldReload(now: t0, pressure: .warning)
        let missing = policy.shouldReload(now: t0.addingTimeInterval(10), pressure: nil)
        let back = policy.shouldReload(now: t0.addingTimeInterval(20), pressure: .warning)
        #expect(!missing)
        #expect(!back)
    }
}
