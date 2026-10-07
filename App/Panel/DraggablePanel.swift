import AppKit

/// デスクトップに貼り付く枠なしパネル。ドラッグ移動を自前で処理し、離した瞬間の速度を通知する。
/// SwiftUI 側のジェスチャーだとウィンドウ移動中に座標系がずれるため、sendEvent で横取りしている。
final class DraggablePanel: NSPanel {
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((CGVector) -> Void)?
    var onDoubleClick: (() -> Void)?

    private static let dragThreshold: CGFloat = 3
    private static let velocityWindow: TimeInterval = 0.1

    private var mouseDownLocation: CGPoint?
    private var originAtMouseDown: CGPoint = .zero
    private var isDragging = false
    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if event.clickCount == 2 {
                onDoubleClick?()
                return
            }
            mouseDownLocation = NSEvent.mouseLocation
            originAtMouseDown = frame.origin
            isDragging = false
            samples = []
            // 吸着アニメーション中でも掴んだ瞬間に止める（割り込み可能）
            onDragBegan?()
        case .leftMouseDragged:
            guard let start = mouseDownLocation else { break }
            let mouse = NSEvent.mouseLocation
            if !isDragging, hypot(mouse.x - start.x, mouse.y - start.y) < Self.dragThreshold { return }
            isDragging = true
            setFrameOrigin(CGPoint(x: originAtMouseDown.x + mouse.x - start.x,
                                   y: originAtMouseDown.y + mouse.y - start.y))
            samples.append((event.timestamp, mouse))
            samples.removeAll { event.timestamp - $0.time > Self.velocityWindow }
            return
        case .leftMouseUp:
            let wasDragging = isDragging
            mouseDownLocation = nil
            isDragging = false
            if wasDragging {
                onDragEnded?(releaseVelocity(at: event.timestamp))
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    /// 直近 0.1 秒の移動から求めた速度（pt/s）。止まってから離した場合は 0。
    private func releaseVelocity(at time: TimeInterval) -> CGVector {
        let recent = samples.filter { time - $0.time <= Self.velocityWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return .zero }
        let dt = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
}
