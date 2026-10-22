import Foundation
import IOKit.ps

/// CPU, memory, battery and disk readings for the stats widget.
@MainActor
enum SystemStats {
    private static var lastTicks: (used: UInt64, total: UInt64)?

    /// CPU use since the previous call, 0...1. The first call returns nil.
    static func cpu() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks   // user, system, idle, nice
        let used = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)
        let total = used + UInt64(t.2)
        defer { lastTicks = (used, total) }
        guard let last = lastTicks, total > last.total, used >= last.used else { return nil }
        return Double(used - last.used) / Double(total - last.total)
    }

    /// Memory in use (active + wired + compressed) and total, in bytes.
    static func memory() -> (used: Double, total: Double)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Double(getpagesize())
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        return (used, Double(ProcessInfo.processInfo.physicalMemory))
    }

    static func battery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (current * 100 / max, (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return nil
    }

    /// Used and total space on the startup disk, in bytes.
    static func disk() -> (used: Double, total: Double)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity,
              let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Double(total) - Double(free), Double(total))
    }

    static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.0f GB", bytes / 1_073_741_824)
    }
}
