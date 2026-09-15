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

    private enum CodingKeys: String, CodingKey {
        case date, period
        case inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
        case totalTokens, totalCost, modelsUsed, modelBreakdowns
    }

    // ccusage 20.x renamed the per-day `date` key to `period`; accept either.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let period = try c.decodeIfPresent(String.self, forKey: .period) {
            date = period
        } else {
            date = try c.decode(String.self, forKey: .date)
        }
        inputTokens = try c.decode(Int.self, forKey: .inputTokens)
        outputTokens = try c.decode(Int.self, forKey: .outputTokens)
        cacheCreationTokens = try c.decode(Int.self, forKey: .cacheCreationTokens)
        cacheReadTokens = try c.decode(Int.self, forKey: .cacheReadTokens)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        totalCost = try c.decode(Double.self, forKey: .totalCost)
        modelsUsed = try c.decode([String].self, forKey: .modelsUsed)
        modelBreakdowns = try c.decode([ModelBreakdown].self, forKey: .modelBreakdowns)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .period)
        try c.encode(inputTokens, forKey: .inputTokens)
        try c.encode(outputTokens, forKey: .outputTokens)
        try c.encode(cacheCreationTokens, forKey: .cacheCreationTokens)
        try c.encode(cacheReadTokens, forKey: .cacheReadTokens)
        try c.encode(totalTokens, forKey: .totalTokens)
        try c.encode(totalCost, forKey: .totalCost)
        try c.encode(modelsUsed, forKey: .modelsUsed)
        try c.encode(modelBreakdowns, forKey: .modelBreakdowns)
    }
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

/// ccusage keys each day as a local-time "yyyy-MM-dd" string.
enum DayKey {
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func string(from date: Date) -> String {
        keyFormatter.string(from: date)
    }

    /// "2026-09-15" -> "Sep 15"
    static func shortLabel(_ key: String) -> String {
        guard let d = keyFormatter.date(from: key) else { return key }
        return labelFormatter.string(from: d)
    }
}

extension DailyUsage {
    var isToday: Bool {
        date == DayKey.string(from: Date())
    }
}

/// "claude-opus-5" -> "Opus"; unknown families pass through unchanged.
func shortModelName(_ modelName: String) -> String {
    let lower = modelName.lowercased()
    if lower.contains("opus") { return "Opus" }
    if lower.contains("haiku") { return "Haiku" }
    if lower.contains("sonnet") { return "Sonnet" }
    if lower.contains("fable") { return "Fable" }
    return modelName
}

extension ModelBreakdown {
    var shortName: String { shortModelName(modelName) }
}

// MARK: - Billing blocks (`ccusage blocks --active --json`)

struct BlocksReport: Decodable {
    let blocks: [UsageBlock]
}

/// ccusage's reconstruction of the 5-hour usage window from local logs. It
/// can't see usage from other machines or claude.ai, nor real plan limits.
struct UsageBlock: Decodable {
    let startTime: Date
    let endTime: Date
    let isActive: Bool
    let costUSD: Double
    let totalTokens: Int
    let burnRate: BurnRate?
    let projection: Projection?

    struct BurnRate: Decodable { let costPerHour: Double }
    struct Projection: Decodable { let totalCost: Double }

    /// ccusage emits ISO 8601 with fractional seconds ("2026-09-15T19:00:00.000Z").
    static let decoder: JSONDecoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unrecognized date: \(s)"))
        }
        return d
    }()
}

extension Double {
    var asCost: String {
        return String(format: "$%.2f", self)
    }

    /// Narrower form for per-bar chart labels: cents only under $10.
    var asShortCost: String {
        return self < 10 ? String(format: "$%.2f", self) : String(format: "$%.0f", self)
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
