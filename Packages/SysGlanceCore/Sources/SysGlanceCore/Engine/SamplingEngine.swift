import Foundation

/// 各 Reader を呼んで差分計算し、1回分の MetricsSnapshot を作る。
public actor SamplingEngine {
    private var cpu = CPUUsageCalculator()
    private var diskRead = CounterRate()
    private var diskWrite = CounterRate()
    private var netDown = CounterRate()
    private var netUp = CounterRate()
    private var processes: [ProcessUsage] = []
    private var lastProcessSample: TimeInterval?
    private var disk: DiskMetrics?
    private var lastDiskSample: TimeInterval?

    private let processInterval: TimeInterval
    private let processLimit: Int
    /// 空き容量の計算（パージ可能領域の集計）は重いので間隔を空ける
    private let diskCapacityInterval: TimeInterval
    /// 単調増加する時刻（秒）。差分計算はこちらを使い、壁時計の変更に影響されないようにする。
    private let clock: @Sendable () -> TimeInterval

    public init(processInterval: TimeInterval = 5, processLimit: Int = 10, diskCapacityInterval: TimeInterval = 30,
                clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.processInterval = processInterval
        self.processLimit = processLimit
        self.diskCapacityInterval = diskCapacityInterval
        self.clock = clock
    }

    /// スリープ復帰時に呼ぶ。次の sample() は基準取得のみになる。
    public func resetBaselines() {
        cpu.reset()
        diskRead.reset()
        diskWrite.reset()
        netDown.reset()
        netUp.reset()
    }

    public func sample(now: Date = Date()) -> MetricsSnapshot {
        let t = clock()

        let cpuUsage = HostReaders.cpuTicks().flatMap { cpu.update($0) }

        var diskIO: Throughput?
        if let bytes = IOReaders.internalDiskBytes() {
            diskIO = Throughput(inbound: diskRead.update(value: bytes.inbound, at: t),
                                outbound: diskWrite.update(value: bytes.outbound, at: t))
        }

        var network: Throughput?
        if let bytes = IOReaders.networkBytes() {
            network = Throughput(inbound: netDown.update(value: bytes.inbound, at: t),
                                 outbound: netUp.update(value: bytes.outbound, at: t))
        }

        if lastProcessSample.map({ t - $0 >= processInterval }) ?? true {
            processes = ProcessReader.topByMemory(limit: processLimit)
            lastProcessSample = t
        }

        if lastDiskSample.map({ t - $0 >= diskCapacityInterval }) ?? true {
            disk = IOReaders.diskCapacity()
            lastDiskSample = t
        }

        return MetricsSnapshot(
            date: now,
            cpu: cpuUsage.map(CPUMetrics.init(usage:)),
            memory: HostReaders.memory(),
            disk: disk,
            diskIO: diskIO,
            network: network,
            battery: IOReaders.battery(),
            uptime: HostReaders.uptime(now: now),
            topProcesses: processes
        )
    }
}
