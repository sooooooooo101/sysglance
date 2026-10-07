import SwiftUI
import SysGlanceCore
import WidgetKit

@main
struct SysGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SysGlanceWidget", provider: SnapshotProvider()) { entry in
            SysGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("SysGlance")
        .description("CPU・メモリ・SSD などの稼働状況")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let envelope: SnapshotEnvelope?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, envelope: SnapshotEnvelope(capturedAt: .now, snapshot: .preview))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(SnapshotEntry(date: .now, envelope: load()))
        }
    }

    /// 同じスナップショットで5分おきのエントリを作り、「○分前」と鮮度判定を進める。
    /// 新しい値は本体アプリの reloadAllTimelines() で届く。
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let envelope = load()
        let entries = (0..<4).map { SnapshotEntry(date: now.addingTimeInterval(Double($0) * 300), envelope: envelope) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }

    private func load() -> SnapshotEnvelope? {
        SnapshotFile.defaultURL().flatMap(SnapshotFile.read(from:))
    }
}

extension MetricsSnapshot {
    /// ウィジェットギャラリー用のサンプル値
    static let preview = MetricsSnapshot(
        date: .now,
        cpu: CPUMetrics(usage: 0.23),
        memory: MemoryMetrics(total: 17_179_869_184, app: 5_000_000_000, wired: 2_500_000_000,
                              compressed: 1_500_000_000, cached: 4_000_000_000,
                              swapUsed: 0, swapTotal: 0, pressure: .normal),
        disk: DiskMetrics(total: 500_000_000_000, available: 180_000_000_000),
        diskIO: Throughput(inbound: 2_400_000, outbound: 800_000),
        network: Throughput(inbound: 1_200_000, outbound: 90_000),
        battery: BatteryMetrics(level: 0.8, isCharging: false, isOnAC: false, minutesRemaining: 300),
        uptime: 2 * 86400 + 5 * 3600,
        topProcesses: [
            ProcessUsage(pid: 1, name: "Safari", memory: 1_500_000_000),
            ProcessUsage(pid: 2, name: "Xcode", memory: 1_200_000_000),
            ProcessUsage(pid: 3, name: "Music", memory: 400_000_000),
        ]
    )
}
