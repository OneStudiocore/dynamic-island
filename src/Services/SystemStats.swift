import Darwin
import Foundation

/// CPU / 内存 / 磁盘采样
final class SystemStats {
    static let shared = SystemStats()

    private var previousTicks: [UInt32] = []

    func cpuUsage() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: UInt32 = 0

        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &numCpus,
                                         &cpuInfo,
                                         &numCpuInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        let stateCount = Int(CPU_STATE_MAX)
        let userIdx = 0, systemIdx = 1, niceIdx = 3, idleIdx = 2
        var ticks: [UInt32] = []
        ticks.reserveCapacity(Int(numCpus) * stateCount)
        for cpu in 0..<Int(numCpus) {
            for state in 0..<stateCount {
                ticks.append(UInt32(info[cpu * stateCount + state]))
            }
        }
        vm_deallocate(mach_task_self_,
                      vm_address_t(bitPattern: info),
                      vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size))

        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count, !previousTicks.isEmpty else { return 0 }

        var busy: Double = 0
        var total: Double = 0
        var i = 0
        while i < ticks.count {
            let user = Double(ticks[i + userIdx]) - Double(previousTicks[i + userIdx])
            let system = Double(ticks[i + systemIdx]) - Double(previousTicks[i + systemIdx])
            let nice = Double(ticks[i + niceIdx]) - Double(previousTicks[i + niceIdx])
            let idle = Double(ticks[i + idleIdx]) - Double(previousTicks[i + idleIdx])
            busy += user + system + nice
            total += user + system + nice + idle
            i += stateCount
        }
        guard total > 0 else { return 0 }
        return min(max(busy / total, 0), 1)
    }

    func memoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(max(used / total, 0), 1)
    }

    func diskFree() -> String {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            return Self.formatter.string(fromByteCount: Int64(bytes))
        }
        return "—"
    }

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useTB]
        f.countStyle = .file
        return f
    }()
}
