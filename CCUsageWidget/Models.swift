import Foundation

// MARK: - JSON Models (codeburn export -f json)

struct CodeburnReport: Codable {
    let generated: String
    let periods: Periods
    let tools: [ToolStat]
    let shellCommands: [ShellCommandStat]
    let projects: [ProjectStat]
}

struct Periods: Codable {
    let today: Period
    let sevenDays: Period
    let thirtyDays: Period

    enum CodingKeys: String, CodingKey {
        case today = "Today"
        case sevenDays = "7 Days"
        case thirtyDays = "30 Days"
    }
}

struct Period: Codable {
    let summary: PeriodSummary
    let daily: [DailyStat]
    let activity: [ActivityStat]
    let models: [ModelStat]
}

struct PeriodSummary: Codable {
    let period: String
    let cost: Double
    let apiCalls: Int
    let sessions: Int

    enum CodingKeys: String, CodingKey {
        case period = "Period"
        case cost = "Cost (USD)"
        case apiCalls = "API Calls"
        case sessions = "Sessions"
    }
}

struct DailyStat: Codable, Identifiable {
    var id: String { date }
    let date: String
    let cost: Double
    let apiCalls: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int

    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case cost = "Cost (USD)"
        case apiCalls = "API Calls"
        case inputTokens = "Input Tokens"
        case outputTokens = "Output Tokens"
        case cacheReadTokens = "Cache Read Tokens"
        case cacheWriteTokens = "Cache Write Tokens"
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}

struct ActivityStat: Codable, Identifiable {
    var id: String { activity }
    let activity: String
    let cost: Double
    let turns: Int

    enum CodingKeys: String, CodingKey {
        case activity = "Activity"
        case cost = "Cost (USD)"
        case turns = "Turns"
    }
}

struct ModelStat: Codable, Identifiable {
    var id: String { model }
    let model: String
    let cost: Double
    let apiCalls: Int
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case model = "Model"
        case cost = "Cost (USD)"
        case apiCalls = "API Calls"
        case inputTokens = "Input Tokens"
        case outputTokens = "Output Tokens"
    }
}

struct ToolStat: Codable, Identifiable {
    var id: String { tool }
    let tool: String
    let calls: Int

    enum CodingKeys: String, CodingKey {
        case tool = "Tool"
        case calls = "Calls"
    }
}

struct ShellCommandStat: Codable, Identifiable {
    var id: String { command }
    let command: String
    let calls: Int

    enum CodingKeys: String, CodingKey {
        case command = "Command"
        case calls = "Calls"
    }
}

struct ProjectStat: Codable, Identifiable {
    var id: String { project }
    let project: String
    let cost: Double
    let apiCalls: Int
    let sessions: Int

    enum CodingKeys: String, CodingKey {
        case project = "Project"
        case cost = "Cost (USD)"
        case apiCalls = "API Calls"
        case sessions = "Sessions"
    }

    /// Short display name — last path component, or a terse fallback for
    /// the long internal Claude agent mode paths.
    var displayName: String {
        if project.contains("/Claude/local/agent/mode/") {
            return "claude agent session"
        }
        let trimmed = project.hasSuffix("/") ? String(project.dropLast()) : project
        return (trimmed as NSString).lastPathComponent
    }
}

// MARK: - Period key

enum PeriodKey: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"

    var id: String { rawValue }
    var short: String {
        switch self {
        case .today: return "1D"
        case .week: return "7D"
        case .month: return "30D"
        }
    }
}

extension Periods {
    func period(for key: PeriodKey) -> Period {
        switch key {
        case .today: return today
        case .week: return sevenDays
        case .month: return thirtyDays
        }
    }
}

// MARK: - Extensions

extension DailyStat {
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

extension ModelStat {
    var shortName: String {
        let lower = model.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("haiku") { return "Haiku" }
        if lower.contains("sonnet") { return "Sonnet" }
        return model
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

    var compact: String {
        let n = Double(self)
        if n >= 1_000_000 {
            return String(format: "%.1fM", n / 1_000_000)
        } else if n >= 10_000 {
            return String(format: "%.0fK", n / 1_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", n / 1_000)
        } else {
            return "\(self)"
        }
    }
}
