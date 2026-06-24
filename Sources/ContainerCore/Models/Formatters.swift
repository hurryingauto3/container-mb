// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum DisplayFormatters {
    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "--" }

        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var amount = Double(value)
        var unitIndex = 0
        while amount >= 1024, unitIndex < units.count - 1 {
            amount /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(value) B"
        }
        return String(format: "%.1f %@", amount, units[unitIndex])
    }

    public static func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f%%", value)
    }

    public static func relativeDate(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "--" }
        let interval = max(0, Int(now.timeIntervalSince(date)))
        if interval < 60 { return "\(interval)s ago" }
        if interval < 3600 { return "\(interval / 60)m ago" }
        if interval < 86400 { return "\(interval / 3600)h ago" }
        return "\(interval / 86400)d ago"
    }

    public static func command(_ command: String?) -> String {
        guard let command, !command.isEmpty else { return "--" }
        return command
    }
}
