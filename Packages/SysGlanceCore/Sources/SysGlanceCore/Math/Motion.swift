import CoreGraphics
import Foundation

/// 臨界減衰スプリング（damping 1.0）。Apple の "response" パラメータで指定する。
/// 解析解で進めるので dt が大きくても発散しない。
public struct CriticalSpring: Sendable {
    public var position: Double
    public var velocity: Double
    public var target: Double
    /// 秒。小さいほど速い。
    public let response: Double

    public init(position: Double, velocity: Double = 0, target: Double, response: Double = 0.35) {
        self.position = position
        self.velocity = velocity
        self.target = target
        self.response = response
    }

    public mutating func step(dt: Double) {
        guard dt > 0 else { return }
        let omega = 2 * Double.pi / response
        let x0 = position - target
        let b = velocity + omega * x0
        let decay = exp(-omega * dt)
        position = target + (x0 + b * dt) * decay
        velocity = (velocity - omega * b * dt) * decay
    }

    public var isSettled: Bool {
        abs(position - target) < 0.5 && abs(velocity) < 5
    }
}

public enum EdgeSnap {
    /// Apple の "Designing Fluid Interfaces" と同じ減速投射。速度(pt/s) → 移動距離(pt)。
    public static func project(velocity: Double, decelerationRate: Double = 0.998) -> Double {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// パネルの着地位置（左下原点）を返す。
    /// 画面端から `threshold` 以内なら端から `margin` の位置へ吸着し、必ず `visible` 内に収める。
    public static func target(for frame: CGRect, in visible: CGRect,
                              threshold: CGFloat = 24, margin: CGFloat = 16) -> CGPoint {
        CGPoint(
            x: axis(min: frame.minX, length: frame.width, lower: visible.minX, upper: visible.maxX,
                    threshold: threshold, margin: margin),
            y: axis(min: frame.minY, length: frame.height, lower: visible.minY, upper: visible.maxY,
                    threshold: threshold, margin: margin)
        )
    }

    private static func axis(min origin: CGFloat, length: CGFloat, lower: CGFloat, upper: CGFloat,
                             threshold: CGFloat, margin: CGFloat) -> CGFloat {
        let maxOrigin = upper - length
        if origin - lower <= threshold { return Swift.min(lower + margin, Swift.max(lower, maxOrigin)) }
        if upper - (origin + length) <= threshold { return Swift.max(maxOrigin - margin, lower) }
        return Swift.min(Swift.max(origin, lower), Swift.max(lower, maxOrigin))
    }
}
