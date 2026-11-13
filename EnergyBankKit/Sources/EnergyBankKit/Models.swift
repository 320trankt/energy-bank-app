import Foundation

/// A calendar day, coded as "yyyy-MM-dd" so stored records and the agent payload stay readable.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 0
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (a: Day, b: Day) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(string) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Expected yyyy-MM-dd, got \(string)"))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// An amount for each of the two banks: deposits, withdrawals, weights or balances.
public struct Banks: Codable, Equatable, Sendable {
    public var mental: Double
    public var physical: Double

    public init(mental: Double, physical: Double) {
        self.mental = mental
        self.physical = physical
    }

    public static let zero = Banks(mental: 0, physical: 0)
}

/// Last night's sleep, merged from HealthKit sources (Fitbit, Bevel, Apple Watch) by the importer.
/// `asleepMinutes` beyond the three stages (a source that doesn't report stages) counts as core.
public struct SleepSummary: Codable, Equatable, Sendable {
    /// The morning the night ends on.
    public var date: Day
    public var inBedStart: Date
    public var inBedEnd: Date
    public var asleepMinutes: Double
    public var deepMinutes: Double
    public var remMinutes: Double
    public var coreMinutes: Double
    public var awakeMinutes: Double
    /// Time to fall asleep: in bed minus asleep at the start of the night.
    public var latencyMinutes: Double
    public var source: String

    public init(date: Day, inBedStart: Date, inBedEnd: Date, asleepMinutes: Double, deepMinutes: Double,
                remMinutes: Double, coreMinutes: Double, awakeMinutes: Double, latencyMinutes: Double,
                source: String) {
        self.date = date
        self.inBedStart = inBedStart
        self.inBedEnd = inBedEnd
        self.asleepMinutes = asleepMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.latencyMinutes = latencyMinutes
        self.source = source
    }
}

/// The category the user assigns to each monitored app or category token. Costs vary by category.
public enum AppCategory: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case social, games, video, news, productivity, other
}

/// One Screen Time threshold callback: a monitored app reached the next rung of its ladder.
/// The cost isn't stored: `EnergyModel` computes it from `MonitorConfig`, so retuned weights
/// re-score past days too.
public struct WithdrawalEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    /// Stable id for the opaque `FamilyActivitySelection` token.
    public var tokenId: String
    public var nickname: String
    public var category: AppCategory
    /// Usage this rung stands for: the minutes since the previous rung.
    public var rungMinutes: Double

    public init(id: UUID = UUID(), timestamp: Date, tokenId: String, nickname: String,
                category: AppCategory, rungMinutes: Double) {
        self.id = id
        self.timestamp = timestamp
        self.tokenId = tokenId
        self.nickname = nickname
        self.category = category
        self.rungMinutes = rungMinutes
    }
}

/// One HealthKit workout. Intensity, physical cost and mental deposit are computed by `EnergyModel`.
public struct WorkoutEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    /// e.g. "climbing", "volleyball", "walking"; keys `MonitorConfig.workoutTypeWeights`.
    public var workoutType: String
    /// Active energy in kcal, when the source recorded it.
    public var activeEnergy: Double?
    /// Average heart rate in bpm, when the source recorded it.
    public var avgHeartRate: Double?

    public init(id: UUID = UUID(), start: Date, end: Date, workoutType: String,
                activeEnergy: Double? = nil, avgHeartRate: Double? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.workoutType = workoutType
        self.activeEnergy = activeEnergy
        self.avgHeartRate = avgHeartRate
    }

    public var durationMinutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

/// A subjective energy rating, the ground truth the model is tuned against.
public struct CheckIn: Codable, Equatable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable { case widget, notification, app }

    public static let levels = 1...10

    public var id: UUID
    public var timestamp: Date
    public var mentalLevel: Int
    public var physicalLevel: Int
    public var source: Source

    /// Nil when a level is outside 1–10.
    public init?(id: UUID = UUID(), timestamp: Date, mentalLevel: Int, physicalLevel: Int, source: Source) {
        guard Self.levels.contains(mentalLevel), Self.levels.contains(physicalLevel) else { return nil }
        self.id = id
        self.timestamp = timestamp
        self.mentalLevel = mentalLevel
        self.physicalLevel = physicalLevel
        self.source = source
    }
}

/// The day's totals for both banks. Deposits include workout deposits into the mental bank.
public struct DailyBalance: Codable, Equatable, Sendable {
    public var date: Day
    public var mentalDeposit: Double
    public var mentalWithdrawals: Double
    public var mentalBalance: Double
    public var physicalDeposit: Double
    public var physicalWithdrawals: Double
    public var physicalBalance: Double

    public init(date: Day, mentalDeposit: Double, mentalWithdrawals: Double, physicalDeposit: Double,
                physicalWithdrawals: Double) {
        self.date = date
        self.mentalDeposit = mentalDeposit
        self.mentalWithdrawals = mentalWithdrawals
        self.mentalBalance = mentalDeposit - mentalWithdrawals
        self.physicalDeposit = physicalDeposit
        self.physicalWithdrawals = physicalWithdrawals
        self.physicalBalance = physicalDeposit - physicalWithdrawals
    }
}

/// The Claude agent's daily read-out, with an optional retuned config the user can accept.
public struct AgentResponse: Codable, Equatable, Sendable {
    public var date: Day
    public var text: String
    public var suggestedConfig: MonitorConfig?

    public init(date: Day, text: String, suggestedConfig: MonitorConfig? = nil) {
        self.date = date
        self.text = text
        self.suggestedConfig = suggestedConfig
    }
}
