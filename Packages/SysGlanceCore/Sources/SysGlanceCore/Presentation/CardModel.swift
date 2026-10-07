import Foundation

/// パネル・ウィジェット・詳細ウィンドウが共通で使う表示モデル。
public struct CardModel: Sendable, Equatable, Identifiable {
    public var kind: MetricKind
    public var title: String
    public var symbol: String
    public var value: String
    /// 複数行可（"\n" 区切り）
    public var detail: String
    public var level: Level
    /// リング表示用の割合（0...1）。割合で表せない項目は nil。
    public var gauge: Double?
    public var accessibilityLabel: String
    public var id: MetricKind { kind }
}

public enum CardModelBuilder {
    public static let placeholder = "—"

    public static func title(of kind: MetricKind) -> String {
        switch kind {
        case .cpu: "CPU"
        case .memory: "メモリ"
        case .network: "ネットワーク"
        case .disk: "SSD"
        case .battery: "バッテリー"
        case .system: "システム"
        }
    }

    public static func symbol(of kind: MetricKind) -> String {
        switch kind {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .system: "clock"
        }
    }

    public static func pressureLabel(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: "正常"
        case .warning: "警告"
        case .critical: "危険"
        }
    }

    /// `kinds` の順に並べる。バッテリーが取得できない（デスクトップMac）場合はバッテリーカードを省く。
    public static func cards(latest: MetricsSnapshot?, kinds: [MetricKind],
                             processLimit: Int = 3) -> [CardModel] {
        kinds.compactMap { kind in
            if kind == .battery, latest?.battery == nil { return nil }
            return card(kind, latest: latest, processLimit: processLimit)
        }
    }

    public static func card(_ kind: MetricKind, latest s: MetricsSnapshot?, processLimit: Int = 3) -> CardModel {
        var c = CardModel(kind: kind, title: title(of: kind), symbol: symbol(of: kind),
                          value: placeholder, detail: "", level: .normal, gauge: nil,
                          accessibilityLabel: "\(title(of: kind)) 取得できません")
        switch kind {
        case .cpu:
            if let cpu = s?.cpu {
                c.value = Fmt.percent(cpu.usage)
                c.gauge = cpu.usage
                c.accessibilityLabel = "CPU 使用率 \(Fmt.percent(cpu.usage))"
            }
        case .memory:
            if let m = s?.memory {
                let used = Fmt.bytes(m.used, base: .binary)
                let total = Fmt.bytes(m.total, base: .binary)
                let pressure = pressureLabel(m.pressure)
                c.value = "\(used) / \(total)"
                c.gauge = Double(m.used) / Double(max(m.total, 1))
                c.detail = "プレッシャー \(pressure) · スワップ \(Fmt.bytes(m.swapUsed, base: .binary))"
                c.level = Thresholds.level(for: m.pressure)
                c.accessibilityLabel = "メモリ \(used) 使用、\(total) 中、プレッシャー\(pressure)"
            }
        case .network:
            if let n = s?.network {
                c.value = "↓ \(Fmt.rate(n.inbound))"
                c.detail = "↑ \(Fmt.rate(n.outbound))"
                c.accessibilityLabel = "ネットワーク 下り \(Fmt.rate(n.inbound))、上り \(Fmt.rate(n.outbound))"
            }
        case .disk:
            if let d = s?.disk {
                let free = Fmt.bytes(d.available, base: .decimal)
                let total = Fmt.bytes(d.total, base: .decimal)
                c.value = "空き \(free)"
                c.gauge = Double(d.used) / Double(max(d.total, 1))
                c.level = Thresholds.level(for: d)
                c.accessibilityLabel = "SSD 空き \(free)、\(total) 中"
                c.detail = "\(total) 中"
            }
            if let io = s?.diskIO {
                let line = "読み \(Fmt.rate(io.inbound)) · 書き \(Fmt.rate(io.outbound))"
                c.detail = c.detail.isEmpty ? line : "\(line)\n\(c.detail)"
                c.accessibilityLabel += "、読み込み \(Fmt.rate(io.inbound))、書き込み \(Fmt.rate(io.outbound))"
            }
        case .battery:
            if let b = s?.battery {
                let state: String
                if b.isCharging {
                    state = "充電中"
                } else if b.isOnAC {
                    state = "電源接続"
                } else if let minutes = b.minutesRemaining {
                    state = "残り \(Fmt.duration(TimeInterval(minutes * 60)))"
                } else {
                    state = "バッテリー駆動"
                }
                c.value = Fmt.percent(b.level)
                c.gauge = b.level
                c.detail = state
                c.level = Thresholds.level(for: b)
                c.symbol = b.isCharging ? "battery.100percent.bolt" : "battery.75percent"
                c.accessibilityLabel = "バッテリー \(Fmt.percent(b.level))、\(state)"
            }
        case .system:
            if let uptime = s?.uptime {
                c.value = "稼働 \(Fmt.duration(uptime))"
                c.accessibilityLabel = "稼働時間 \(Fmt.duration(uptime))"
            }
            let top = Array((s?.topProcesses ?? []).prefix(processLimit))
            if !top.isEmpty {
                c.detail = top.map { "\($0.name)  \(Fmt.bytes($0.memory, base: .binary))" }.joined(separator: "\n")
                c.accessibilityLabel += "、メモリ使用量上位 " + top.map(\.name).joined(separator: "、")
            }
        }
        return c
    }
}
