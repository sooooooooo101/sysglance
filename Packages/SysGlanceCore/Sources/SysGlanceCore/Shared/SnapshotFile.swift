import Foundation

public struct SnapshotEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var capturedAt: Date
    public var snapshot: MetricsSnapshot

    public init(schemaVersion: Int = SnapshotFile.schemaVersion, capturedAt: Date, snapshot: MetricsSnapshot) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.snapshot = snapshot
    }
}

/// 本体アプリ → ウィジェットへ最新値を渡す共有ファイル。
public enum SnapshotFile {
    public static let appGroupID = "FJW7DK8RB4.com.soshi.sysglance"
    public static let fileName = "snapshot.json"
    public static let schemaVersion = 1
    /// これより古いスナップショットは「本体が起動していない」とみなす
    public static let staleAfter: TimeInterval = 600

    public enum DecodeError: Error, Equatable {
        case unsupportedSchema(Int)
    }

    public static func defaultURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    public static func encode(_ snapshot: MetricsSnapshot, capturedAt: Date) throws -> Data {
        let envelope = SnapshotEnvelope(schemaVersion: schemaVersion, capturedAt: capturedAt, snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> SnapshotEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
        guard envelope.schemaVersion == schemaVersion else {
            throw DecodeError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope
    }

    public static func write(_ snapshot: MetricsSnapshot, capturedAt: Date, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(snapshot, capturedAt: capturedAt).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> SnapshotEnvelope? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    public static func isStale(_ envelope: SnapshotEnvelope, now: Date) -> Bool {
        now.timeIntervalSince(envelope.capturedAt) >= staleAfter
    }
}

/// ウィジェットのタイムライン再読込は OS の予算を消費するため、呼ぶ条件を絞る。
public struct WidgetReloadPolicy: Sendable {
    public static let minimumInterval: TimeInterval = 300
    private var lastReload: Date?
    private var lastPressure: MemoryPressure?

    public init() {}

    /// true を返したら呼び出し側は再読込すること（状態は記録済み）。
    public mutating func shouldReload(now: Date, pressure: MemoryPressure?) -> Bool {
        let pressureChanged = pressure != nil && lastPressure != nil && pressure != lastPressure
        if pressure != nil { lastPressure = pressure }
        let due = lastReload.map { now.timeIntervalSince($0) >= Self.minimumInterval } ?? true
        guard due || pressureChanged else { return false }
        lastReload = now
        return true
    }
}
