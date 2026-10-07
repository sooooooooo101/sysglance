import Darwin
import Foundation

/// メモリ使用量の多いプロセス。他ユーザー（root 等）のプロセスは権限上読めないので含まれない。
public enum ProcessReader {
    public static func topByMemory(limit: Int) -> [ProcessUsage] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }

        var usages: [ProcessUsage] = []
        usages.reserveCapacity(Int(filled))
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { continue }
            usages.append(ProcessUsage(pid: pid, name: name(of: pid), memory: info.ri_phys_footprint))
        }
        return top(usages, limit: limit)
    }

    /// メモリ降順、同値なら pid 昇順で先頭 limit 件。
    public static func top(_ usages: [ProcessUsage], limit: Int) -> [ProcessUsage] {
        Array(usages.sorted { $0.memory != $1.memory ? $0.memory > $1.memory : $0.pid < $1.pid }.prefix(max(0, limit)))
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(nulTerminated: buffer) : "pid \(pid)"
    }
}
