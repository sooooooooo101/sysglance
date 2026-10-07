import Foundation

public enum MetricKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, memory, network, disk, battery, system
    public var id: String { rawValue }
}

public enum Level: Int, Codable, Sendable, Comparable {
    case normal, warning, critical
    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum MemoryPressure: Int, Codable, Sendable {
    case normal = 1, warning = 2, critical = 4

    /// `kern.memorystatus_vm_pressure_level` の値から変換する。未知の値は normal 扱い。
    public init(sysctlValue: Int32) {
        switch sysctlValue {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }
}

public struct CPUMetrics: Codable, Sendable, Equatable {
    /// 0...1
    public var usage: Double
    public init(usage: Double) { self.usage = usage }
}

public struct MemoryMetrics: Codable, Sendable, Equatable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure

    /// アクティビティモニタの「使用済みメモリ」と同じ定義（App + Wired + 圧縮）。
    public var used: UInt64 { app + wired + compressed }

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64,
                swapUsed: UInt64, swapTotal: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressure = pressure
    }
}

public struct DiskMetrics: Codable, Sendable, Equatable {
    public var total: UInt64
    public var available: UInt64
    public var used: UInt64 { total >= available ? total - available : 0 }
    public init(total: UInt64, available: UInt64) {
        self.total = total
        self.available = available
    }
}

public struct Throughput: Codable, Sendable, Equatable {
    /// bytes/s
    public var inbound: Double
    /// bytes/s
    public var outbound: Double
    public init(inbound: Double, outbound: Double) {
        self.inbound = inbound
        self.outbound = outbound
    }
}

public struct BatteryMetrics: Codable, Sendable, Equatable {
    /// 0...1
    public var level: Double
    public var isCharging: Bool
    public var isOnAC: Bool
    public var minutesRemaining: Int?
    public init(level: Double, isCharging: Bool, isOnAC: Bool, minutesRemaining: Int?) {
        self.level = level
        self.isCharging = isCharging
        self.isOnAC = isOnAC
        self.minutesRemaining = minutesRemaining
    }
}

public struct ProcessUsage: Codable, Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    /// phys_footprint（アクティビティモニタの「メモリ」列と同じ）
    public var memory: UInt64
    public var id: Int32 { pid }
    public init(pid: Int32, name: String, memory: UInt64) {
        self.pid = pid
        self.name = name
        self.memory = memory
    }
}

public struct MetricsSnapshot: Codable, Sendable, Equatable {
    public var date: Date
    public var cpu: CPUMetrics?
    public var memory: MemoryMetrics?
    public var disk: DiskMetrics?
    /// inbound = 読み込み, outbound = 書き込み
    public var diskIO: Throughput?
    /// inbound = 下り, outbound = 上り
    public var network: Throughput?
    public var battery: BatteryMetrics?
    public var uptime: TimeInterval?
    public var topProcesses: [ProcessUsage]

    public init(date: Date, cpu: CPUMetrics? = nil, memory: MemoryMetrics? = nil, disk: DiskMetrics? = nil,
                diskIO: Throughput? = nil, network: Throughput? = nil, battery: BatteryMetrics? = nil,
                uptime: TimeInterval? = nil, topProcesses: [ProcessUsage] = []) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.diskIO = diskIO
        self.network = network
        self.battery = battery
        self.uptime = uptime
        self.topProcesses = topProcesses
    }
}
