import Darwin
import Foundation
import IOKit
import IOKit.ps

/// SSD・ネットワーク・バッテリー（IOKit / sysctl）
public enum IOReaders {
    public struct ByteCounters: Sendable, Equatable {
        public var inbound: UInt64
        public var outbound: UInt64
        public init(inbound: UInt64, outbound: UInt64) {
            self.inbound = inbound
            self.outbound = outbound
        }
    }

    public static func diskCapacity(path: String = "/") -> DiskMetrics? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage,
              total > 0, available >= 0 else { return nil }
        return DiskMetrics(total: UInt64(total), available: UInt64(available))
    }

    /// 内蔵ストレージの累積読み書きバイト数。inbound = 読み込み, outbound = 書き込み。
    /// ディスクイメージ（Physical Interconnect Location が "File" 等）は二重計上になるので除外する。
    public static func internalDiskBytes() -> ByteCounters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard isInternal(driver: service),
                  let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                      .takeRetainedValue() as? [String: Any] else { continue }
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            found = true
        }
        return found ? ByteCounters(inbound: read, outbound: written) : nil
    }

    private static func isInternal(driver: io_object_t) -> Bool {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(driver, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(parent) }
        let characteristics = IORegistryEntryCreateCFProperty(parent, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        return characteristics?["Physical Interconnect Location"] as? String == "Internal"
    }

    private static let excludedInterfacePrefixes = ["lo", "utun", "awdl", "llw", "bridge", "anpi", "gif", "stf"]

    /// VPN（utun）などの仮想IFは物理IFと二重計上になるので数えない。
    public static func isCountedInterface(name: String, isLoopback: Bool) -> Bool {
        guard !isLoopback else { return false }
        return !excludedInterfacePrefixes.contains { name.hasPrefix($0) }
    }

    /// 全物理IFの累積バイト数（64bitカウンタ）。inbound = 受信, outbound = 送信。
    public static func networkBytes() -> ByteCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var inbound: UInt64 = 0
        var outbound: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        let name = String(nulTerminated: nameBuffer)
                        let loopback = info.ifm_flags & IFF_LOOPBACK != 0
                        if isCountedInterface(name: name, isLoopback: loopback) {
                            inbound &+= info.ifm_data.ifi_ibytes
                            outbound &+= info.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return ByteCounters(inbound: inbound, outbound: outbound)
    }

    /// 内蔵バッテリーがなければ nil。
    public static func battery() -> BatteryMetrics? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = d[kIOPSTimeToEmptyKey] as? Int
            return BatteryMetrics(
                level: min(max(Double(current) / Double(maximum), 0), 1),
                isCharging: d[kIOPSIsChargingKey] as? Bool ?? false,
                isOnAC: onAC,
                // -1 は「計算中」
                minutesRemaining: (!onAC && (minutes ?? -1) > 0) ? minutes : nil
            )
        }
        return nil
    }
}
