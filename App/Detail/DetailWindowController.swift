import AppKit
import SwiftUI

@MainActor
final class DetailWindowController {
    private let store: MetricsStore
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
            window.contentViewController = NSHostingController(rootView: DetailView(store: store))
            window.setContentSize(NSSize(width: 880, height: 580))
            window.center()
            window.setFrameAutosaveName("SysGlanceDetail")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
