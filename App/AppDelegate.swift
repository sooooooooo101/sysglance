import AppKit
import SysGlanceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricsStore()
    private let settings = PanelSettings()
    private let publisher = SnapshotPublisher()
    private lazy var detail = DetailWindowController(store: store)
    private var panel: DesktopPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onSample = { [publisher] snapshot in publisher.publish(snapshot) }
        let panel = DesktopPanelController(store: store, settings: settings) { [weak self] in
            self?.detail.show()
        }
        panel.show()
        self.panel = panel
        store.start()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.stop() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.start(resetBaselines: true) }
        }
    }

    /// ウィジェットのタップ（sysglance://detail）
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "sysglance" }) {
            detail.show()
        }
    }

    /// Finder や Spotlight から再度起動されたときは詳細ウィンドウを開く
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        detail.show()
        return false
    }
}
