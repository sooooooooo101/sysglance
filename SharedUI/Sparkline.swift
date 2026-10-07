import SwiftUI

/// 直近の推移を描く小さな折れ線。最新値が右端に来るよう、データが少ないうちは右寄せで描く。
/// Canvas は CPU ラスタライズになり毎秒の再描画が重いため、GPU で描かれる Shape で実装する。
struct Sparkline: View {
    let series: [[Double]]
    /// nil なら観測最大値で自動スケール（ただし最低 1 KB/s 相当にしてノイズを拡大しない）
    let maxValue: Double?
    let capacity: Int
    let tint: Color

    private static let autoScaleFloor = 1_000.0

    var body: some View {
        let observed = series.flatMap { $0 }.max() ?? 0
        let peak = maxValue ?? max(observed, Self.autoScaleFloor)
        ZStack {
            ForEach(Array(series.enumerated()), id: \.offset) { index, values in
                SparklineShape(values: values, peak: peak, capacity: capacity)
                    .stroke(index == 0 ? tint : tint.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct SparklineShape: Shape {
    let values: [Double]
    let peak: Double
    let capacity: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard peak > 0, capacity > 1, values.count > 1 else { return path }
        let step = rect.width / CGFloat(capacity - 1)
        let visible = values.suffix(capacity)
        let offset = CGFloat(capacity - visible.count)
        for (i, value) in visible.enumerated() {
            let ratio = CGFloat(min(max(value / peak, 0), 1))
            let point = CGPoint(x: rect.minX + (offset + CGFloat(i)) * step,
                                y: rect.maxY - 1 - ratio * (rect.height - 2))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
