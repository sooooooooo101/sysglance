import AppKit
import SysGlanceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricsStore()
    private let publisher = SnapshotPublisher()
    private lazy var detail = DetailWindowController(store: store)
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // ログイン時の自動起動では詳細ウィンドウを出さず、裏でウィジェット用の計測だけ行う
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == AEEventID(kAEOpenApplication),
           event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            launchedAsLoginItem = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onSample = { [publisher] snapshot in publisher.publish(snapshot) }
        store.start()
        if !launchedAsLoginItem {
            detail.show()
        }

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
