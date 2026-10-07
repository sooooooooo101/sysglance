import AppKit
import SwiftUI
import SysGlanceCore

@MainActor
final class DesktopPanelController: NSObject {
    static let screenMargin: CGFloat = 16

    private let panel: DraggablePanel
    private let hosting: NSHostingView<PanelView>
    private let settings: PanelSettings
    private var springX: CriticalSpring?
    private var springY: CriticalSpring?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    init(store: MetricsStore, settings: PanelSettings, openDetail: @escaping @MainActor () -> Void) {
        self.settings = settings
        panel = DraggablePanel(contentRect: CGRect(origin: .zero, size: settings.size.size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hosting = NSHostingView(rootView: PanelView(store: store, settings: settings, openDetail: openDetail))
        super.init()

        // 壁紙・デスクトップアイコンより上、通常ウィンドウより下
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        hosting.sizingOptions = []
        panel.contentView = hosting

        panel.onDragBegan = { [weak self] in self?.stopAnimation() }
        panel.onDragEnded = { [weak self] velocity in self?.settle(velocity: velocity) }
        panel.onDoubleClick = openDetail

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show() {
        let size = settings.size.size
        let main = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = PanelPlacement.restoredOrigin(saved: settings.panelOrigin, size: size,
                                                   screens: NSScreen.screens.map(\.visibleFrame), main: main,
                                                   margin: Self.screenMargin)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        observeSize()
    }

    /// サイズ変更時は左上を固定して伸縮し、画面からはみ出したら吸着で戻す
    private func observeSize() {
        withObservationTracking {
            _ = settings.size
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let frame = self.panel.frame
                let size = self.settings.size.size
                self.panel.setFrame(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
                                    display: true)
                self.settle(velocity: .zero)
                self.observeSize()
            }
        }
    }

    @objc private func screensChanged() {
        // ディスプレイが外れた等で画面外に出たパネルを戻す
        settle(velocity: .zero)
    }

    private func settle(velocity: CGVector) {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        var projected = panel.frame
        projected.origin.x += EdgeSnap.project(velocity: velocity.dx)
        projected.origin.y += EdgeSnap.project(velocity: velocity.dy)
        let target = EdgeSnap.target(for: projected, in: visible, margin: Self.screenMargin)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrameOrigin(target)
            settings.panelOrigin = target
            return
        }
        springX = CriticalSpring(position: panel.frame.minX, velocity: velocity.dx, target: target.x)
        springY = CriticalSpring(position: panel.frame.minY, velocity: velocity.dy, target: target.y)
        if displayLink == nil, let view = panel.contentView {
            let link = view.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = lastTimestamp.map { now - $0 } ?? (1.0 / 60)
        lastTimestamp = now
        guard var x = springX, var y = springY else {
            stopAnimation()
            return
        }
        x.step(dt: dt)
        y.step(dt: dt)
        springX = x
        springY = y
        if x.isSettled && y.isSettled {
            let target = CGPoint(x: x.target, y: y.target)
            panel.setFrameOrigin(target)
            settings.panelOrigin = target
            stopAnimation()
        } else {
            panel.setFrameOrigin(CGPoint(x: x.position, y: y.position))
        }
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        springX = nil
        springY = nil
    }
}
