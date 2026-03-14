import Foundation

enum Formatting {
    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        if total < 60 {
            return "\(total)s"
        }
        if total < 3600 {
            let m = total / 60
            let s = total % 60
            return "\(m)m \(s)s"
        }
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h)h \(m)m"
    }

    static func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }

    static func formatPercentage(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    static func formatHealthScore(_ score: Double) -> String {
        String(format: "%.3f", score)
    }

    static func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
