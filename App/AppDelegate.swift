import AppKit
import SysGlanceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricsStore()
    private let publisher = SnapshotPublisher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onSample = { [publisher] snapshot in publisher.publish(snapshot) }
        store.start()
    }
}
