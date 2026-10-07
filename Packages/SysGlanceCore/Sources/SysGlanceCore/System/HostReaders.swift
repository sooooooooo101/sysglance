import Darwin
import Foundation

/// メモリ・CPU・稼働時間（Mach / sysctl）
public enum HostReaders {
    public static func memory() -> MemoryMetrics? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let page = UInt64(pageSize)

        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (anonymous >= purgeable ? anonymous - purgeable : 0) * page

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let pressure: MemoryPressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0
            ? MemoryPressure(sysctlValue: level) : .normal

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0

        return MemoryMetrics(
            total: ProcessInfo.processInfo.physicalMemory,
            app: app,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cached: (UInt64(stats.external_page_count) + purgeable) * page,
            swapUsed: swapOK ? swap.xsu_used : 0,
            swapTotal: swapOK ? swap.xsu_total : 0,
            pressure: pressure
        )
    }

    public static func cpuTicks() -> CPUTicks? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(load.cpu_ticks.0),    // CPU_STATE_USER
            system: UInt64(load.cpu_ticks.1),  // CPU_STATE_SYSTEM
            idle: UInt64(load.cpu_ticks.2),    // CPU_STATE_IDLE
            nice: UInt64(load.cpu_ticks.3)     // CPU_STATE_NICE
        )
    }

    public static func uptime(now: Date = Date()) -> TimeInterval? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        let bootDate = Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
        return max(0, now.timeIntervalSince(bootDate))
    }
}
