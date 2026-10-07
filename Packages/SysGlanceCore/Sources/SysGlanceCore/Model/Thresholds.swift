public enum Thresholds {
    public static func level(for pressure: MemoryPressure) -> Level {
        switch pressure {
        case .normal: .normal
        case .warning: .warning
        case .critical: .critical
        }
    }

    /// 空き 10% 未満で warning、5% 未満で critical。
    public static func level(for disk: DiskMetrics) -> Level {
        guard disk.total > 0 else { return .normal }
        let ratio = Double(disk.available) / Double(disk.total)
        if ratio < 0.05 { return .critical }
        if ratio < 0.10 { return .warning }
        return .normal
    }

    /// 電源未接続で 20% 未満なら warning、10% 未満なら critical。
    public static func level(for battery: BatteryMetrics) -> Level {
        guard !battery.isOnAC else { return .normal }
        if battery.level < 0.10 { return .critical }
        if battery.level < 0.20 { return .warning }
        return .normal
    }
}
