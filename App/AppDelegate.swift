import AppKit
import SysGlanceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricsStore()
    private let publisher = SnapshotPublisher()
    private lazy var detail = DetailWindowController(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onSample = { [publisher] snapshot in publisher.publish(snapshot) }
        store.start()
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
