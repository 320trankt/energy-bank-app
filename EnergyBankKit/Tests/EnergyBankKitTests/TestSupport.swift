import Foundation
@testable import EnergyBankKit

let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

let today = Day(year: 2026, month: 11, day: 12)!

/// A time on `today`, in UTC.
func at(_ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour, minute: minute))!
}

func night(asleep: Double, deep: Double = 0, rem: Double = 0, core: Double = 0,
           awake: Double = 0, latency: Double = 0) -> SleepSummary {
    SleepSummary(date: today, inBedStart: at(0).addingTimeInterval(-3600), inBedEnd: at(7),
                 asleepMinutes: asleep, deepMinutes: deep, remMinutes: rem, coreMinutes: core,
                 awakeMinutes: awake, latencyMinutes: latency, source: "Bevel")
}

func rung(_ nickname: String, _ category: AppCategory, at time: Date, minutes: Double = 15) -> WithdrawalEvent {
    WithdrawalEvent(timestamp: time, tokenId: "token-\(nickname)", nickname: nickname, category: category,
                    rungMinutes: minutes)
}

func workout(_ type: String, from start: Date, minutes: Double, heartRate: Double? = nil,
             kcal: Double? = nil) -> WorkoutEvent {
    WorkoutEvent(start: start, end: start.addingTimeInterval(minutes * 60), workoutType: type,
                 activeEnergy: kcal, avgHeartRate: heartRate)
}
