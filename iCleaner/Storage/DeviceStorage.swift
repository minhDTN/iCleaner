import Foundation

// Reads free/total disk space for the device. Used by the paywall's storage
// usage bar ("X GB of Y GB used"). Values come from URLResourceKey on the
// home directory volume — same numbers iOS Settings shows.
enum DeviceStorage {
    /// (usedGB, totalGB, freeGB). Returns nil on failure (rare).
    static func snapshot() -> (used: Double, total: Double, free: Double)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let totalBytes = values.volumeTotalCapacity else { return nil }

        // Apple recommends `volumeAvailableCapacityForImportantUsageKey` for
        // "what the system would let an app use" — slightly different from raw
        // free space but closer to user-visible free.
        let freeBytes = Int(values.volumeAvailableCapacityForImportantUsage ?? Int64(0))
        let usedBytes = max(0, totalBytes - freeBytes)

        let toGB: (Int) -> Double = { Double($0) / 1_073_741_824 }  // 1024^3
        return (toGB(usedBytes), toGB(totalBytes), toGB(freeBytes))
    }
}
