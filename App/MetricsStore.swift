import Foundation
import Observation
import SysGlanceCore

@MainActor
@Observable
final class MetricsStore {
    /// 1秒間隔で30分
    static let historyCapacity = 1800

    private(set) var history = RingBuffer<MetricsSnapshot>(capacity: historyCapacity)
    var latest: MetricsSnapshot? { history.last }

    @ObservationIgnored var onSample: ((MetricsSnapshot) -> Void)?
    @ObservationIgnored private let engine = SamplingEngine()
    @ObservationIgnored private var loop: Task<Void, Never>?

    func start(resetBaselines: Bool = false) {
        guard loop == nil else { return }
        loop = Task { [weak self, engine] in
            if resetBaselines { await engine.resetBaselines() }
            while !Task.isCancelled {
                let snapshot = await engine.sample()
                guard let self, !Task.isCancelled else { return }
                self.history.append(snapshot)
                self.onSample?(snapshot)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}
