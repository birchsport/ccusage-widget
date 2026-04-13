import Foundation

// MARK: - JSON Models

struct UsageReport: Codable {
    let daily: [DailyUsage]
    let totals: UsageTotals
}

struct DailyUsage: Codable, Identifiable {
    var id: String { date }
    let date: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let modelsUsed: [String]
    let modelBreakdowns: [ModelBreakdown]
}

struct ModelBreakdown: Codable, Identifiable {
    var id: String { modelName }
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double
}

struct UsageTotals: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalCost: Double
    let totalTokens: Int
}

// MARK: - Extensions

extension DailyUsage {
    var shortDate: String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.locale = Locale(identifier: "en_US_POSIX")
        guard let d = input.date(from: date) else { return date }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        out.locale = Locale(identifier: "en_US_POSIX")
        return out.string(from: d)
    }

    var isToday: Bool {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.locale = Locale(identifier: "en_US_POSIX")
        guard let d = input.date(from: date) else { return false }
        return Calendar.current.isDateInToday(d)
    }
}

extension ModelBreakdown {
    var shortName: String {
        let lower = modelName.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("haiku") { return "Haiku" }
        if lower.contains("sonnet") { return "Sonnet" }
        return modelName
    }
}

extension Double {
    var asCost: String {
        return String(format: "$%.2f", self)
    }
}

extension Int {
    var compactTokens: String {
        let n = Double(self)
        if n >= 1_000_000_000 {
            return String(format: "%.1fB", n / 1_000_000_000)
        } else if n >= 1_000_000 {
            return String(format: "%.1fM", n / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.0fK", n / 1_000)
        } else {
            return "\(self)"
        }
    }
}
