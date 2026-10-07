import CoreGraphics

public enum PanelPlacement {
    /// 保存位置の半分以上が見えていなければ掴めないとみなして既定位置へ戻す
    public static let minimumVisibleFraction: CGFloat = 0.5

    /// 起動時のパネル位置（左下原点）。
    /// - saved: 前回保存した位置。nil なら既定位置（メイン画面の右上）。
    /// - screens: 各画面の visibleFrame。
    public static func restoredOrigin(saved: CGPoint?, size: CGSize, screens: [CGRect], main: CGRect,
                                      margin: CGFloat = 16) -> CGPoint {
        let fallback = CGPoint(x: main.maxX - size.width - margin, y: main.maxY - size.height - margin)
        guard let saved, size.width > 0, size.height > 0 else { return fallback }
        let frame = CGRect(origin: saved, size: size)
        let best = screens
            .map { screen -> (CGRect, CGFloat) in
                let overlap = screen.intersection(frame)
                return (screen, overlap.isNull ? 0 : overlap.width * overlap.height)
            }
            .max { $0.1 < $1.1 }
        guard let (screen, area) = best,
              area >= size.width * size.height * minimumVisibleFraction else { return fallback }
        return EdgeSnap.target(for: frame, in: screen, margin: margin)
    }
}
