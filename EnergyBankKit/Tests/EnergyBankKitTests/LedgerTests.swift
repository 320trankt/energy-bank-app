import XCTest
@testable import EnergyBankKit

final class LedgerTests: XCTestCase {
    private let model = EnergyModel()
    private let sleep = night(asleep: 420, deep: 80, rem: 100, core: 240, awake: 20, latency: 25)
    private let volleyball = workout("volleyball", from: at(18), minutes: 150, heartRate: 175)
    private let walk = workout("walking", from: at(21), minutes: 30)

    private func day() -> DayLedger {
        // Deliberately out of order: the ledger sorts by time (workouts count at their end).
        model.ledger(
            day: today, sleep: sleep,
            withdrawals: [rung("Instagram", .social, at: at(21)), rung("Instagram", .social, at: at(9)),
                          rung("YouTube", .video, at: at(12))],
            workouts: [walk, volleyball])
    }

    func testReplaysTheDayInTimeOrder() {
        let ledger = day()
        XCTAssertEqual(ledger.entries.map(\.cause), [
            .sleep,
            .screenTime(nickname: "Instagram", category: .social),
            .screenTime(nickname: "YouTube", category: .video),
            .workout(type: "volleyball"),
            .screenTime(nickname: "Instagram", category: .social),
            .workout(type: "walking"),
        ])
        XCTAssertEqual(ledger.entries.map(\.time), [at(7), at(9), at(12), at(20, 30), at(21), at(21, 30)])
    }

    func testRunningBalancesAndTotals() {
        let ledger = day()
        let sleepDeposit = model.sleepDeposit(sleep)
        // Volleyball: 150 min × 0.3 × 1.8 (zone 5) = 81 physical, leaving 15.875 before the walk.
        let physicalBeforeWalk = sleepDeposit.physical - 81
        XCTAssertEqual(ledger.entries[3].balance.physical, physicalBeforeWalk, accuracy: 1e-9)

        // The walk starts with a low physical bank, so its mental benefit is scaled down.
        let walkEffect = model.workoutEffect(walk, physicalBalance: physicalBeforeWalk)
        XCTAssertEqual(ledger.entries[5].change.mental, walkEffect.mentalDeposit, accuracy: 1e-9)
        XCTAssertLessThan(walkEffect.mentalDeposit, model.workoutEffect(walk, physicalBalance: 100).mentalDeposit)

        let total = ledger.total
        XCTAssertEqual(total.date, today)
        XCTAssertEqual(total.mentalWithdrawals, 6 + 4.5 + 6, accuracy: 1e-9)
        XCTAssertEqual(total.physicalWithdrawals, 81 + 9, accuracy: 1e-9)
        XCTAssertEqual(total.physicalDeposit, sleepDeposit.physical, accuracy: 1e-9)
        let volleyballDeposit = model.workoutEffect(volleyball, physicalBalance: sleepDeposit.physical).mentalDeposit
        XCTAssertEqual(total.mentalDeposit, sleepDeposit.mental + volleyballDeposit + walkEffect.mentalDeposit,
                       accuracy: 1e-9)
        XCTAssertEqual(total.mentalBalance, ledger.entries.last!.balance.mental, accuracy: 1e-9)
        XCTAssertEqual(total.physicalBalance, ledger.entries.last!.balance.physical, accuracy: 1e-9)
    }

    func testTopDrainsAddUpEachApp() {
        let drains = day().topDrains()
        XCTAssertEqual(drains.map(\.nickname), ["Instagram", "YouTube"])
        XCTAssertEqual(drains[0].cost, 12, accuracy: 1e-9)
        XCTAssertEqual(drains[1].cost, 4.5, accuracy: 1e-9)
        XCTAssertEqual(day().topDrains(limit: 1).map(\.nickname), ["Instagram"])
    }

    func testWithoutSleepTheDayStartsEmptyAndCanGoNegative() {
        let ledger = model.ledger(day: today, sleep: nil, withdrawals: [rung("Instagram", .social, at: at(9))],
                                  workouts: [])
        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.total.mentalBalance, -6, accuracy: 1e-9)
        XCTAssertEqual(ledger.total.physicalBalance, 0)
    }
}
