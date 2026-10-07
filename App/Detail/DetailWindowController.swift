import AppKit
import Observation
import SwiftUI
import SysGlanceCore

/// 詳細ウィンドウで選択中の項目。表示を作り直しても保つため、ビューの外に置く。
@MainActor
@Observable
final class DetailState {
    var selection: MetricKind? = .cpu
}

@MainActor
final class DetailWindowController: NSObject, NSWindowDelegate {
    private let store: MetricsStore
    private let loginItem = LoginItem()
    private let state = DetailState()
    private var window: NSWindow?

    init(store: MetricsStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "SysGlance"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("SysGlanceDetail")
            self.window = window
        }
        attachContent()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // ウィンドウが見えていない間も SwiftUI が毎秒の履歴更新を監視し続けると、
    // 常駐 CPU が 2% を超える。見えない間は表示を外し、見えたら作り直す。

    func windowWillClose(_ notification: Notification) {
        detachContent()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        if window.occlusionState.contains(.visible) {
            attachContent()
        } else {
            detachContent()
        }
    }

    private func attachContent() {
        guard let window, window.contentViewController == nil else { return }
        let frame = window.frame
        let hosting = NSHostingController(rootView: DetailView(store: store, loginItem: loginItem, state: state))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setFrame(frame, display: true)
    }

    private func detachContent() {
        guard let window, window.contentViewController != nil else { return }
        let frame = window.frame
        window.contentViewController = nil
        window.setFrame(frame, display: false)
    }
}
