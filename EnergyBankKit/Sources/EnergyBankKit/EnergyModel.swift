import Foundation

/// The two-bank model from DESIGN.md: sleep deposits into both banks, screen time withdraws
/// from the mental bank, and workouts withdraw from the physical bank while depositing into the
/// mental one, less so when the physical bank is nearly empty.
public struct EnergyModel: Sendable {
    public var config: MonitorConfig

    public init(config: MonitorConfig = MonitorConfig()) {
        self.config = config
    }

    // MARK: Sleep

    /// Last night's deposit into each bank: minutes asleep weighted by stage, minus penalties for
    /// long latency and time awake. Never negative.
    public func sleepDeposit(_ sleep: SleepSummary) -> Banks {
        let staged = sleep.coreMinutes + sleep.deepMinutes + sleep.remMinutes
        let core = sleep.coreMinutes + max(0, sleep.asleepMinutes - staged)
        let latency = max(0, sleep.latencyMinutes - config.latencyGraceMinutes)
        let penalty = latency * config.latencyPenaltyPerMinute + sleep.awakeMinutes * config.awakePenaltyPerMinute
        let w = config.stageWeights

        func deposit(_ bank: KeyPath<Banks, Double>) -> Double {
            let weighted = core * w.core[keyPath: bank] + sleep.deepMinutes * w.deep[keyPath: bank]
                + sleep.remMinutes * w.rem[keyPath: bank]
            return max(0, weighted - penalty) * config.pointsPerWeightedMinute
        }
        return Banks(mental: deposit(\.mental), physical: deposit(\.physical))
    }

    // MARK: Screen time

    /// Mental cost of one threshold rung.
    public func mentalCost(_ event: WithdrawalEvent) -> Double {
        let rate = config.mentalCostPerMinute[event.category] ?? config.mentalCostPerMinute[.other] ?? 0
        return max(0, event.rungMinutes) * rate
    }

    // MARK: Workouts

    /// Intensity from heart rate zones, else active energy per minute, else 1 (duration only).
    public func intensity(_ workout: WorkoutEvent) -> Double {
        if let hr = workout.avgHeartRate, hr > 0, config.maxHeartRate > 0, !config.heartRateZoneIntensity.isEmpty {
            let fraction = hr / config.maxHeartRate
            let zone = config.heartRateZoneBounds.firstIndex { fraction < $0 } ?? config.heartRateZoneBounds.count
            return config.heartRateZoneIntensity[min(zone, config.heartRateZoneIntensity.count - 1)]
        }
        if let kcal = workout.activeEnergy, kcal > 0, workout.durationMinutes > 0, config.referenceKcalPerMinute > 0 {
            let perMinute = kcal / workout.durationMinutes
            return min(config.maxIntensity, max(config.minIntensity, perMinute / config.referenceKcalPerMinute))
        }
        return 1
    }

    /// A workout's physical cost and mental deposit. `physicalBalance` is the physical bank just
    /// before the workout, which scales the mental benefit down when it's low.
    public func workoutEffect(_ workout: WorkoutEvent, physicalBalance: Double) -> (physicalCost: Double, mentalDeposit: Double) {
        let weights = config.workoutTypeWeights[workout.workoutType] ?? WorkoutWeights()
        let minutes = workout.durationMinutes
        let physicalCost = minutes * config.physicalCostPerMinute * intensity(workout) * weights.physical

        let tau = config.mentalDepositTimeConstantMinutes
        let saturation = tau > 0 ? 1 - exp(-minutes / tau) : 1
        var mentalDeposit = config.maxMentalDepositPerWorkout * saturation * weights.mental
        if config.lowPhysicalThreshold > 0, physicalBalance < config.lowPhysicalThreshold {
            mentalDeposit *= max(0, physicalBalance) / config.lowPhysicalThreshold
        }
        return (physicalCost, mentalDeposit)
    }

    // MARK: The day

    /// Replays the day in time order: the sleep deposit at wake-up, then each withdrawal and
    /// workout (at its end). Balances may go below zero. Pass only the day's events.
    public func ledger(day: Day, sleep: SleepSummary?, withdrawals: [WithdrawalEvent],
                       workouts: [WorkoutEvent]) -> DayLedger {
        enum Item { case withdrawal(WithdrawalEvent), workout(WorkoutEvent) }
        let items = (withdrawals.map { ($0.timestamp, Item.withdrawal($0)) } + workouts.map { ($0.end, Item.workout($0)) })
            .enumerated()
            .sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }
            .map(\.element)

        var entries: [DayLedger.Entry] = []
        var balance = Banks.zero
        var deposits = Banks.zero
        var withdrawn = Banks.zero

        if let sleep {
            let deposit = sleepDeposit(sleep)
            balance = deposit
            deposits = deposit
            entries.append(.init(time: sleep.inBedEnd, cause: .sleep, change: deposit, balance: balance))
        }
        for (time, item) in items {
            let change: Banks
            let cause: DayLedger.Entry.Cause
            switch item {
            case .withdrawal(let event):
                let cost = mentalCost(event)
                withdrawn.mental += cost
                change = Banks(mental: -cost, physical: 0)
                cause = .screenTime(nickname: event.nickname, category: event.category)
            case .workout(let workout):
                let effect = workoutEffect(workout, physicalBalance: balance.physical)
                withdrawn.physical += effect.physicalCost
                deposits.mental += effect.mentalDeposit
                change = Banks(mental: effect.mentalDeposit, physical: -effect.physicalCost)
                cause = .workout(type: workout.workoutType)
            }
            balance.mental += change.mental
            balance.physical += change.physical
            entries.append(.init(time: time, cause: cause, change: change, balance: balance))
        }

        let total = DailyBalance(date: day, mentalDeposit: deposits.mental, mentalWithdrawals: withdrawn.mental,
                                 physicalDeposit: deposits.physical, physicalWithdrawals: withdrawn.physical)
        return DayLedger(entries: entries, total: total)
    }
}

/// One day replayed: every change in time order (the drain curves) and the day's totals.
public struct DayLedger: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public enum Cause: Equatable, Sendable {
            case sleep
            case screenTime(nickname: String, category: AppCategory)
            case workout(type: String)
        }

        public var time: Date
        public var cause: Cause
        /// Signed: negative for withdrawals.
        public var change: Banks
        /// Both balances after this entry.
        public var balance: Banks
    }

    public var entries: [Entry]
    public var total: DailyBalance

    /// Apps by total mental cost today, largest first (ties by name).
    public func topDrains(limit: Int = 5) -> [(nickname: String, cost: Double)] {
        var costs: [String: Double] = [:]
        for entry in entries {
            if case .screenTime(let nickname, _) = entry.cause {
                costs[nickname, default: 0] -= entry.change.mental
            }
        }
        return costs.map { (nickname: $0.key, cost: $0.value) }
            .sorted { $0.cost != $1.cost ? $0.cost > $1.cost : $0.nickname < $1.nickname }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
