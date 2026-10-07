import AppKit
import SysGlanceCore

/// デスクトップに貼り付く枠なしパネル。ドラッグ移動を自前で処理し、離した瞬間の速度を通知する。
/// SwiftUI 側のジェスチャーだとウィンドウ移動中に座標系がずれるため、sendEvent で横取りしている。
final class DraggablePanel: NSPanel {
    /// 掴んだ瞬間に呼ぶ。吸着アニメーションを止めたら true を返す（割り込み可能）。
    var onDragBegan: (() -> Bool)?
    var onDragEnded: ((CGVector) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var tracker = DragTracker()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let interrupted = onDragBegan?() ?? false
            if event.clickCount == 2 {
                onDoubleClick?()
            }
            tracker.begin(mouse: NSEvent.mouseLocation, origin: frame.origin, interruptedAnimation: interrupted)
            if event.clickCount == 2 { return }
        case .leftMouseDragged:
            if let origin = tracker.move(mouse: NSEvent.mouseLocation, at: event.timestamp) {
                setFrameOrigin(origin)
                return
            }
        case .leftMouseUp:
            if case let .settle(velocity) = tracker.end(at: event.timestamp) {
                onDragEnded?(velocity)
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}
