import Foundation
import Darwin

/// 实时网速采样：累加所有活跃接口的收发字节，按采样间隔换算成每秒速率
final class NetworkStats {
    static let shared = NetworkStats()

    private var lastDown: UInt64 = 0
    private var lastUp: UInt64 = 0
    private var lastStamp = Date()
    private(set) var downPerSec: Double = 0
    private(set) var upPerSec: Double = 0

    func sample() {
        let (down, up) = Self.totals()
        let now = Date()
        let dt = max(now.timeIntervalSince(lastStamp), 0.2)

        if lastDown > 0 || lastUp > 0 {
            downPerSec = down >= lastDown ? Double(down - lastDown) / dt : 0
            upPerSec = up >= lastUp ? Double(up - lastUp) / dt : 0
        }
        lastDown = down
        lastUp = up
        lastStamp = now
    }

    /// 累加各接口收发字节（跳过回环）
    private static func totals() -> (UInt64, UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        var cursor = first
        while true {
            let entry = cursor.pointee
            if let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: entry.ifa_name)
                if name != "lo0", let raw = entry.ifa_data {
                    let data = raw.assumingMemoryBound(to: if_data.self).pointee
                    down &+= UInt64(data.ifi_ibytes)
                    up &+= UInt64(data.ifi_obytes)
                }
            }
            guard let next = entry.ifa_next else { break }
            cursor = next
        }
        return (down, up)
    }

    /// 速率格式化：B/s → K/M
    static func pretty(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 * 1024 { return String(format: "%.0f K/s", bytesPerSec / 1024) }
        return String(format: "%.1f M/s", bytesPerSec / 1024 / 1024)
    }
}
