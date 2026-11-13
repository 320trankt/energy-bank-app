import Foundation

/// Every weight, cost and coupling factor in the model, so the user or the Claude agent can tune
/// them against check-ins instead of changing code. The defaults are starting points, not fitted
/// values (DESIGN.md, Open Questions). Points are scaled so a full night fills a bank to about 100.
public struct MonitorConfig: Codable, Equatable, Sendable {
    // MARK: Threshold ladder

    /// Rung size for closely watched apps.
    public var watchedRungMinutes: Double = 5
    /// Rung size for everything else.
    public var defaultRungMinutes: Double = 15
    /// Threshold events per `DeviceActivitySchedule` before the ladder is re-registered.
    public var maxEventsPerSchedule: Int = 20

    // MARK: Sleep deposit

    /// Weight per minute asleep in each stage, per bank.
    public var stageWeights = StageWeights()
    /// Latency up to this many minutes isn't penalized.
    public var latencyGraceMinutes: Double = 15
    /// Weighted minutes lost per minute of latency past the grace period.
    public var latencyPenaltyPerMinute: Double = 0.5
    /// Weighted minutes lost per minute awake during the night.
    public var awakePenaltyPerMinute: Double = 0.5
    /// 8 hours of core-weighted sleep deposits 100 points.
    public var pointsPerWeightedMinute: Double = 100.0 / 480

    // MARK: Screen time (mental withdrawals)

    /// Mental points per minute of use, by category. Missing categories fall back to `.other`.
    public var mentalCostPerMinute: [AppCategory: Double] = [
        .social: 0.4, .games: 0.4, .video: 0.3, .news: 0.3, .other: 0.2, .productivity: 0.1,
    ]

    // MARK: Workouts

    /// Physical points per minute at intensity 1.
    public var physicalCostPerMinute: Double = 0.3
    /// The most a single workout can deposit into the mental bank.
    public var maxMentalDepositPerWorkout: Double = 20
    /// Diminishing returns: a workout this long deposits about 63% of the maximum.
    public var mentalDepositTimeConstantMinutes: Double = 30
    /// Per-type multipliers, e.g. climbing costing more physically than walking.
    public var workoutTypeWeights: [String: WorkoutWeights] = [:]
    /// For heart rate zones.
    public var maxHeartRate: Double = 190
    /// Upper bounds of zones 1–4 as fractions of `maxHeartRate`; above the last is zone 5.
    public var heartRateZoneBounds: [Double] = [0.6, 0.7, 0.8, 0.9]
    /// Intensity for zones 1–5.
    public var heartRateZoneIntensity: [Double] = [0.5, 0.8, 1.0, 1.4, 1.8]
    /// Active kcal per minute that counts as intensity 1, when there's no heart rate.
    public var referenceKcalPerMinute: Double = 8
    public var minIntensity: Double = 0.25
    public var maxIntensity: Double = 2.5

    // MARK: Coupling

    /// Below this physical balance a workout's mental benefit shrinks in proportion, reaching
    /// zero at an empty physical bank.
    public var lowPhysicalThreshold: Double = 30

    public init() {}
}

public struct StageWeights: Codable, Equatable, Sendable {
    public var core = Banks(mental: 1.0, physical: 1.0)
    public var deep = Banks(mental: 1.2, physical: 1.5)
    public var rem = Banks(mental: 1.5, physical: 1.2)

    public init() {}
}

public struct WorkoutWeights: Codable, Equatable, Sendable {
    public var physical: Double
    public var mental: Double

    public init(physical: Double = 1, mental: Double = 1) {
        self.physical = physical
        self.mental = mental
    }
}
