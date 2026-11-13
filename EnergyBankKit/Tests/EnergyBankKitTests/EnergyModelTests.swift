import XCTest
@testable import EnergyBankKit

final class EnergyModelTests: XCTestCase {
    private let model = EnergyModel()

    // MARK: Sleep deposit

    func testTypicalNightIsWeightedByStageForEachBank() {
        // Mental: 240 + 80×1.2 + 100×1.5 = 486; physical: 240 + 80×1.5 + 100×1.2 = 480.
        // Penalty: (25 − 15)×0.5 latency + 20×0.5 awake = 15 weighted minutes.
        let deposit = model.sleepDeposit(night(asleep: 420, deep: 80, rem: 100, core: 240, awake: 20, latency: 25))
        XCTAssertEqual(deposit.mental, 471 * 100 / 480, accuracy: 1e-9)
        XCTAssertEqual(deposit.physical, 465 * 100 / 480, accuracy: 1e-9)
    }

    func testDeepCountsMoreForTheBodyAndREMForTheMind() {
        let deep = model.sleepDeposit(night(asleep: 100, deep: 100))
        let rem = model.sleepDeposit(night(asleep: 100, rem: 100))
        XCTAssertGreaterThan(deep.physical, deep.mental)
        XCTAssertGreaterThan(rem.mental, rem.physical)
    }

    func testUnstagedSleepCountsAsCore() {
        let unstaged = model.sleepDeposit(night(asleep: 420))
        XCTAssertEqual(unstaged, model.sleepDeposit(night(asleep: 420, core: 420)))
        XCTAssertEqual(unstaged.mental, 87.5, accuracy: 1e-9)
    }

    func testLatencyIsFreeWithinTheGracePeriod() {
        XCTAssertEqual(model.sleepDeposit(night(asleep: 420, latency: 15)), model.sleepDeposit(night(asleep: 420)))
        let slow = model.sleepDeposit(night(asleep: 420, latency: 35))
        XCTAssertEqual(slow.mental, (420 - 10) * 100 / 480, accuracy: 1e-9)
    }

    func testDepositIsNeverNegative() {
        XCTAssertEqual(model.sleepDeposit(night(asleep: 10, awake: 300)), .zero)
    }

    // MARK: Screen time

    func testRungCostDependsOnCategory() {
        XCTAssertEqual(model.mentalCost(rung("Instagram", .social, at: at(9))), 6, accuracy: 1e-9)
        XCTAssertEqual(model.mentalCost(rung("Notes", .productivity, at: at(9))), 1.5, accuracy: 1e-9)

        var config = MonitorConfig()
        config.mentalCostPerMinute[.games] = nil
        let cost = EnergyModel(config: config).mentalCost(rung("Chess", .games, at: at(9)))
        XCTAssertEqual(cost, 15 * 0.2, accuracy: 1e-9, "a category without a cost falls back to .other")
    }

    // MARK: Workouts

    func testIntensityComesFromHeartRateZonesFirst() {
        XCTAssertEqual(model.intensity(workout("walking", from: at(8), minutes: 30, heartRate: 100)), 0.5)
        XCTAssertEqual(model.intensity(workout("running", from: at(8), minutes: 30, heartRate: 150)), 1.0)
        XCTAssertEqual(model.intensity(workout("volleyball", from: at(8), minutes: 30, heartRate: 175)), 1.8)
        XCTAssertEqual(model.intensity(workout("running", from: at(8), minutes: 60, heartRate: 150, kcal: 1200)), 1.0)
    }

    func testIntensityFallsBackToActiveEnergyThenDuration() {
        XCTAssertEqual(model.intensity(workout("walking", from: at(8), minutes: 60, kcal: 240)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(model.intensity(workout("running", from: at(8), minutes: 60, kcal: 1200)), 2.5, "capped")
        XCTAssertEqual(model.intensity(workout("yoga", from: at(8), minutes: 60, kcal: 30)), 0.25, "floored")
        XCTAssertEqual(model.intensity(workout("yoga", from: at(8), minutes: 60)), 1)
    }

    func testMentalDepositHasDiminishingReturns() {
        let half = model.workoutEffect(workout("walking", from: at(8), minutes: 30), physicalBalance: 100)
        let full = model.workoutEffect(workout("walking", from: at(8), minutes: 60), physicalBalance: 100)
        XCTAssertEqual(full.mentalDeposit, 20 * (1 - exp(-2)), accuracy: 1e-9)
        XCTAssertLessThan(full.mentalDeposit, 2 * half.mentalDeposit)
        XCTAssertEqual(full.physicalCost, 60 * 0.3, accuracy: 1e-9)
    }

    func testLowPhysicalBankShrinksTheMentalBenefit() {
        let walk = workout("walking", from: at(8), minutes: 60)
        let rested = model.workoutEffect(walk, physicalBalance: 100)
        let tired = model.workoutEffect(walk, physicalBalance: 15)
        XCTAssertEqual(tired.mentalDeposit, rested.mentalDeposit / 2, accuracy: 1e-9)
        XCTAssertEqual(tired.physicalCost, rested.physicalCost)
        XCTAssertEqual(model.workoutEffect(walk, physicalBalance: -5).mentalDeposit, 0)
    }

    func testWorkoutTypesCarryTheirOwnWeights() {
        var config = MonitorConfig()
        config.workoutTypeWeights["climbing"] = WorkoutWeights(physical: 1.5, mental: 1.2)
        let tuned = EnergyModel(config: config)
        let climb = workout("climbing", from: at(8), minutes: 60)
        let plain = model.workoutEffect(climb, physicalBalance: 100)
        let weighted = tuned.workoutEffect(climb, physicalBalance: 100)
        XCTAssertEqual(weighted.physicalCost, plain.physicalCost * 1.5, accuracy: 1e-9)
        XCTAssertEqual(weighted.mentalDeposit, plain.mentalDeposit * 1.2, accuracy: 1e-9)
    }
}
