import Foundation

/// 表示用フォーマッタ。ロケールに依存しない決定的な出力にする（テスト容易性のため）。
public enum Fmt {
    public enum Base: Double, Sendable {
        /// メモリ（アクティビティモニタと同じ 1024 基準）
        case binary = 1024
        /// ストレージ・通信速度（Finder と同じ 1000 基準）
        case decimal = 1000
    }

    private static let units = ["B", "KB", "MB", "GB", "TB"]

    public static func bytes(_ value: UInt64, base: Base) -> String {
        var v = Double(value)
        var i = 0
        // 999.5 で繰り上げることで "1000 KB" や "1020 KB" のような表示を避ける
        while v >= 999.5, i < units.count - 1 {
            v /= base.rawValue
            i += 1
        }
        if i == 0 { return "\(value) B" }
        return String(format: v >= 99.95 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        let clamped = bytesPerSecond.isFinite ? min(max(0, bytesPerSecond), 1e18) : 0
        return bytes(UInt64(clamped.rounded()), base: .decimal) + "/s"
    }

    /// 0...1 → "42%"
    public static func percent(_ fraction: Double) -> String {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// "3日 4時間" / "4時間 12分" / "12分"
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0)) / 60
        let days = total / (60 * 24)
        let hours = (total / 60) % 24
        let minutes = total % 60
        if days > 0 { return "\(days)日 \(hours)時間" }
        if hours > 0 { return "\(hours)時間 \(minutes)分" }
        return "\(minutes)分"
    }

    /// "たった今" / "3分前" / "2時間前"
    public static func ago(from date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "たった今" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)分前" }
        return "\(minutes / 60)時間前"
    }
}
