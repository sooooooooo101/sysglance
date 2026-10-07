import SwiftUI
import SysGlanceCore

/// ウィジェットのサイズごとに表示する項目。
enum LayoutSize: Sendable {
    case small, medium, large

    var kinds: [MetricKind] {
        switch self {
        case .small: [.cpu, .memory]
        case .medium: [.cpu, .memory, .disk, .network]
        case .large: MetricKind.allCases
        }
    }
}

/// サイズごとのレイアウト。余白・背景は containerBackground が持つ。
struct MetricsLayout: View {
    let size: LayoutSize
    let cards: [CardModel]
    /// "3分前" など
    let footer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch size {
            case .small:
                SmallLayout(cards: cards)
            case .medium:
                MediumLayout(cards: cards)
            case .large:
                LargeLayout(cards: cards)
            }
            if let footer {
                Spacer(minLength: 4)
                Text(footer).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SmallLayout: View {
    let cards: [CardModel]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(cards) { card in
                RingStat(card: card)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RingStat: View {
    let card: CardModel

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(max(card.gauge ?? 0, 0), 1))
                    .stroke(card.level.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(card.gauge.map(Fmt.percent) ?? CardModelBuilder.placeholder)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            HStack(spacing: 2) {
                Text(card.title)
                if let badge = card.level.badgeSymbol {
                    Image(systemName: badge).foregroundStyle(card.level.tint)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
    }
}

private struct MediumLayout: View {
    let cards: [CardModel]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { i in
                GridRow {
                    CompactCell(card: cards[i])
                    if i + 1 < cards.count {
                        CompactCell(card: cards[i + 1])
                    }
                }
            }
        }
    }
}

/// Medium 用：タイトルと値
private struct CompactCell: View {
    let card: CardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardHeader(card: card)
            CardValue(card: card, font: .system(.callout, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
    }
}

private struct LargeLayout: View {
    let cards: [CardModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cards) { card in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        CardHeader(card: card)
                        CardValue(card: card, font: .system(.callout, design: .rounded).weight(.semibold))
                        if card.kind == .system || card.kind == .disk, !card.detail.isEmpty {
                            Text(card.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(card.kind == .system ? 3 : 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(card.accessibilityLabel)
            }
        }
    }
}

private struct CardHeader: View {
    let card: CardModel

    var body: some View {
        Label(card.title, systemImage: card.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct CardValue: View {
    let card: CardModel
    let font: Font

    var body: some View {
        HStack(spacing: 4) {
            Text(card.kind == .network ? "\(card.value)  \(card.detail)" : card.value)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let badge = card.level.badgeSymbol {
                Image(systemName: badge).font(.caption).foregroundStyle(card.level.tint)
            }
        }
    }
}
