import XCTest
@testable import EnergyBankKit

final class CodingTests: XCTestCase {
    func testDayCodesAsAPlainDateString() throws {
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(today), as: UTF8.self), "\"2026-11-12\"")
        XCTAssertEqual(try JSONDecoder().decode(Day.self, from: Data("\"2026-11-12\"".utf8)), today)
        XCTAssertThrowsError(try JSONDecoder().decode(Day.self, from: Data("\"12/11/2026\"".utf8)))
        for bad in ["2026-13-01", "2026-1-05", "2026-11-12-01", "", "x"] {
            XCTAssertNil(Day(bad), bad)
        }
        XCTAssertEqual(Day(at(23, 59), calendar: utc), today)
        XCTAssertLessThan(today, Day("2026-12-01")!)
    }

    func testConfigRoundTripsWithCategoriesKeyedByName() throws {
        var config = MonitorConfig()
        config.workoutTypeWeights["climbing"] = WorkoutWeights(physical: 1.5, mental: 1.2)
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(MonitorConfig.self, from: data), config)

        // Readable for the agent: {"social": 0.4, ...}, not a flat [key, value, ...] array.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let costs = try XCTUnwrap(json["mentalCostPerMinute"] as? [String: Double])
        XCTAssertEqual(costs["social"], 0.4)
        XCTAssertEqual(Set(costs.keys), Set(AppCategory.allCases.map(\.rawValue)))
    }

    func testAgentResponseRoundTripsWithASuggestedConfig() throws {
        var suggested = MonitorConfig()
        suggested.mentalCostPerMinute[.video] = 0.5
        let response = AgentResponse(date: today, text: "Video was today's biggest drain.", suggestedConfig: suggested)
        let decoded = try JSONDecoder().decode(AgentResponse.self, from: JSONEncoder().encode(response))
        XCTAssertEqual(decoded, response)
    }

    func testCheckInLevelsAreOneToTen() {
        XCTAssertNil(CheckIn(timestamp: at(9), mentalLevel: 0, physicalLevel: 5, source: .widget))
        XCTAssertNil(CheckIn(timestamp: at(9), mentalLevel: 5, physicalLevel: 11, source: .widget))
        XCTAssertNotNil(CheckIn(timestamp: at(9), mentalLevel: 1, physicalLevel: 10, source: .notification))
    }

    func testDailyBalanceIsDepositMinusWithdrawals() {
        let balance = DailyBalance(date: today, mentalDeposit: 90, mentalWithdrawals: 30,
                                   physicalDeposit: 80, physicalWithdrawals: 20)
        XCTAssertEqual(balance.mentalBalance, 60)
        XCTAssertEqual(balance.physicalBalance, 60)
    }
}
