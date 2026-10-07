import SwiftUI
import SysGlanceCore
import WidgetKit

struct SysGlanceWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var size: LayoutSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }

    var body: some View {
        Group {
            if let envelope = entry.envelope, !SnapshotFile.isStale(envelope, now: entry.date) {
                MetricsLayout(size: size,
                              cards: CardModelBuilder.cards(latest: envelope.snapshot, history: [], kinds: size.kinds),
                              sparklineCapacity: 0,
                              footer: Fmt.ago(from: envelope.capturedAt, now: entry.date))
            } else {
                StaleView()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "sysglance://detail"))
    }
}

private struct StaleView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "pause.circle").font(.title2).foregroundStyle(.secondary)
            Text("SysGlanceが起動していません").font(.caption).multilineTextAlignment(.center)
            Text("クリックして起動").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
