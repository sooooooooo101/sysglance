import Charts
import SwiftUI
import SysGlanceCore

struct DetailView: View {
    let store: MetricsStore
    let loginItem: LoginItem
    @Bindable var state: DetailState

    var body: some View {
        NavigationSplitView {
            List(MetricKind.allCases, selection: $state.selection) { kind in
                Label(CardModelBuilder.title(of: kind), systemImage: CardModelBuilder.symbol(of: kind))
                    .tag(kind)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            if let kind = state.selection {
                DetailPane(kind: kind, store: store)
            } else {
                ContentUnavailableView("項目を選択してください", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("ログイン時に起動", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    ))
                    Divider()
                    Button("SysGlance を終了") { NSApp.terminate(nil) }
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }
        }
    }
}

private struct DetailPane: View {
    let kind: MetricKind
    let store: MetricsStore

    var body: some View {
        let latest = store.latest
        let card = CardModelBuilder.card(kind, latest: latest, processLimit: 10)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.largeTitle.bold())
                    HStack(spacing: 6) {
                        Text(card.value).font(.title2.weight(.semibold)).monospacedDigit()
                        if let badge = card.level.badgeSymbol {
                            Image(systemName: badge).foregroundStyle(card.level.tint)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                let chart = ChartData.make(for: kind, history: store.history.elements)
                if !chart.series.isEmpty {
                    HistoryChart(data: chart)
                        .frame(height: 240)
                }
                Breakdown(kind: kind, latest: latest)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Chart

struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct ChartData {
    var series: [(name: String, points: [ChartPoint])]
    var yMax: Double?
    var format: (Double) -> String

    /// 30分 × 1Hz = 最大1800点。描画負荷を抑えるため最大360点程度に間引く。
    static func make(for kind: MetricKind, history: [MetricsSnapshot]) -> ChartData {
        let stride = max(1, history.count / 360)
        let sampled = Swift.stride(from: 0, to: history.count, by: stride).map { history[$0] }
        func line(_ name: String, _ value: (MetricsSnapshot) -> Double?) -> (name: String, points: [ChartPoint]) {
            (name, sampled.compactMap { s in value(s).map { ChartPoint(date: s.date, value: $0) } })
        }
        switch kind {
        case .cpu:
            return ChartData(series: [line("CPU") { $0.cpu?.usage }], yMax: 1, format: Fmt.percent)
        case .memory:
            return ChartData(series: [line("使用済み") { s in s.memory.map { Double($0.used) / Double(max($0.total, 1)) } }],
                             yMax: 1, format: Fmt.percent)
        case .network:
            return ChartData(series: [line("下り") { $0.network?.inbound }, line("上り") { $0.network?.outbound }],
                             yMax: nil, format: Fmt.rate)
        case .disk:
            return ChartData(series: [line("読み込み") { $0.diskIO?.inbound }, line("書き込み") { $0.diskIO?.outbound }],
                             yMax: nil, format: Fmt.rate)
        case .battery:
            return ChartData(series: [line("残量") { $0.battery?.level }], yMax: 1, format: Fmt.percent)
        case .system:
            return ChartData(series: [], yMax: nil, format: { _ in "" })
        }
    }
}

private struct HistoryChart: View {
    let data: ChartData
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(data.series, id: \.name) { series in
                ForEach(series.points) { point in
                    LineMark(x: .value("時刻", point.date), y: .value("値", point.value))
                        .foregroundStyle(by: .value("系列", series.name))
                        .interpolationMethod(.monotone)
                }
            }
            if let selectedDate {
                RuleMark(x: .value("時刻", selectedDate))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        tooltip(at: selectedDate)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...(data.yMax ?? max(observedMax, 1_000)))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(data.format(v)) }
                }
            }
        }
    }

    private var observedMax: Double {
        data.series.flatMap { $0.points.map(\.value) }.max() ?? 0
    }

    private func tooltip(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date, format: .dateTime.hour().minute().second()).font(.caption2).foregroundStyle(.secondary)
            ForEach(data.series, id: \.name) { series in
                if let nearest = series.points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
                    Text("\(series.name) \(data.format(nearest.value))").font(.caption).monospacedDigit()
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
    }
}

// MARK: - Breakdown

private struct Breakdown: View {
    let kind: MetricKind
    let latest: MetricsSnapshot?

    var body: some View {
        switch kind {
        case .memory:
            if let m = latest?.memory {
                rows([
                    ("App メモリ", Fmt.bytes(m.app, base: .binary)),
                    ("確保されているメモリ（Wired）", Fmt.bytes(m.wired, base: .binary)),
                    ("圧縮", Fmt.bytes(m.compressed, base: .binary)),
                    ("キャッシュ", Fmt.bytes(m.cached, base: .binary)),
                    ("スワップ使用量", "\(Fmt.bytes(m.swapUsed, base: .binary)) / \(Fmt.bytes(m.swapTotal, base: .binary))"),
                    ("メモリプレッシャー", CardModelBuilder.pressureLabel(m.pressure)),
                ])
            }
        case .disk:
            if let d = latest?.disk {
                rows([
                    ("容量", Fmt.bytes(d.total, base: .decimal)),
                    ("使用済み", Fmt.bytes(d.used, base: .decimal)),
                    ("空き", Fmt.bytes(d.available, base: .decimal)),
                ])
            }
        case .battery:
            if let b = latest?.battery {
                rows([
                    ("残量", Fmt.percent(b.level)),
                    ("電源", b.isOnAC ? "電源アダプタ" : "バッテリー"),
                    ("状態", b.isCharging ? "充電中" : "充電していません"),
                ])
            } else {
                Text("このMacにはバッテリーがありません").foregroundStyle(.secondary)
            }
        case .system:
            VStack(alignment: .leading, spacing: 8) {
                if let uptime = latest?.uptime {
                    rows([("稼働時間", Fmt.duration(uptime))])
                }
                Text("メモリ使用量の多いプロセス").font(.headline).padding(.top, 8)
                Text("他のユーザー（システム）のプロセスは含まれません").font(.caption).foregroundStyle(.secondary)
                rows((latest?.topProcesses ?? []).map { ($0.name, Fmt.bytes($0.memory, base: .binary)) })
            }
        case .cpu, .network:
            EmptyView()
        }
    }

    private func rows(_ items: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                GridRow {
                    Text(item.0).foregroundStyle(.secondary)
                    Text(item.1).monospacedDigit()
                }
            }
        }
    }
}
