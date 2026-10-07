import Foundation

/// 単調増加する累積カウンタから毎秒の速度を求める。
/// カウンタの減少（スリープ復帰・IF再接続など）や経過時間0以下では 0 を返し、基準を更新する。
public struct CounterRate: Sendable {
    private var lastValue: UInt64?
    private var lastTime: TimeInterval = 0

    public init() {}

    public mutating func update(value: UInt64, at time: TimeInterval) -> Double {
        defer {
            lastValue = value
            lastTime = time
        }
        guard let previous = lastValue else { return 0 }
        let elapsed = time - lastTime
        guard elapsed > 0, value >= previous else { return 0 }
        return Double(value - previous) / elapsed
    }

    public mutating func reset() { lastValue = nil }
}

public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// 前回の tick との差分から CPU 使用率（0...1）を求める。
public struct CPUUsageCalculator: Sendable {
    private var last: CPUTicks?

    public init() {}

    /// 初回とカウンタ巻き戻り時は nil。
    public mutating func update(_ ticks: CPUTicks) -> Double? {
        defer { last = ticks }
        guard let last else { return nil }
        guard ticks.user >= last.user, ticks.system >= last.system,
              ticks.idle >= last.idle, ticks.nice >= last.nice else { return nil }
        let busy = Double((ticks.user - last.user) + (ticks.system - last.system) + (ticks.nice - last.nice))
        let idle = Double(ticks.idle - last.idle)
        let total = busy + idle
        guard total > 0 else { return 0 }
        return min(max(busy / total, 0), 1)
    }

    public mutating func reset() { last = nil }
}
