import Foundation
import os
import SysGlanceCore
import WidgetKit

/// ウィジェット用に最新値を App Group へ書き出す。
@MainActor
final class SnapshotPublisher {
    static let writeInterval: TimeInterval = 30

    private let url: URL?
    private var lastWrite: Date?
    private var policy = WidgetReloadPolicy()
    private let logger = Logger(subsystem: "com.soshi.sysglance", category: "snapshot")

    init(url: URL? = SnapshotFile.defaultURL()) {
        self.url = url
        if url == nil {
            logger.error("App Group container is unavailable; widget will not update")
        }
    }

    func publish(_ snapshot: MetricsSnapshot, now: Date = Date()) {
        guard let url else { return }
        let writeDue = lastWrite.map { now.timeIntervalSince($0) >= Self.writeInterval } ?? true
        let reload = policy.shouldReload(now: now, pressure: snapshot.memory?.pressure)
        guard writeDue || reload else { return }
        do {
            try SnapshotFile.write(snapshot, capturedAt: now, to: url)
            lastWrite = now
        } catch {
            logger.error("Failed to write snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }
        if reload {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
