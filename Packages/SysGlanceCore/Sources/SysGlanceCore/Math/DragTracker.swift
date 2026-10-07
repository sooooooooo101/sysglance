import CoreGraphics
import Foundation

/// パネルのドラッグ判定（画面座標・左下原点）。AppKit のイベント処理から切り離してテストできるようにしている。
public struct DragTracker: Sendable {
    public static let threshold: CGFloat = 3
    public static let velocityWindow: TimeInterval = 0.1

    public enum Release: Equatable, Sendable {
        /// 何もしない（ただのクリック）
        case none
        /// この速度（pt/s）を引き継いで吸着させる
        case settle(velocity: CGVector)
    }

    private var start: CGPoint?
    private var originAtStart: CGPoint = .zero
    private var interruptedAnimation = false
    private var isDragging = false
    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    public init() {}

    /// - interruptedAnimation: 掴んだことで吸着アニメーションを止めたか
    public mutating func begin(mouse: CGPoint, origin: CGPoint, interruptedAnimation: Bool) {
        start = mouse
        originAtStart = origin
        self.interruptedAnimation = interruptedAnimation
        isDragging = false
        samples = []
    }

    /// ドラッグ中ならパネルの新しい原点を返す。閾値未満の移動や開始前は nil。
    public mutating func move(mouse: CGPoint, at time: TimeInterval) -> CGPoint? {
        guard let start else { return nil }
        if !isDragging, hypot(mouse.x - start.x, mouse.y - start.y) < Self.threshold { return nil }
        isDragging = true
        samples.append((time, mouse))
        samples.removeAll { time - $0.time > Self.velocityWindow }
        return CGPoint(x: originAtStart.x + mouse.x - start.x, y: originAtStart.y + mouse.y - start.y)
    }

    public mutating func end(at time: TimeInterval) -> Release {
        defer {
            start = nil
            isDragging = false
            interruptedAnimation = false
            samples = []
        }
        guard start != nil else { return .none }
        if isDragging { return .settle(velocity: releaseVelocity(at: time)) }
        // 吸着の途中で止めたままにすると中途半端な位置に残り、保存もされない
        return interruptedAnimation ? .settle(velocity: .zero) : .none
    }

    /// 直近 0.1 秒の移動から求めた速度。止まってから離した場合は 0。
    private func releaseVelocity(at time: TimeInterval) -> CGVector {
        let recent = samples.filter { time - $0.time <= Self.velocityWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return .zero }
        let dt = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
}
