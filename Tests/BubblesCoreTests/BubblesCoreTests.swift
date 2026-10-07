import XCTest
@testable import BubblesCore

final class BubblesCoreTests: XCTestCase {
    func testUTCOffsetParsing() {
        XCTAssertEqual(ClockTools.parseUTCOffset("UTC+1"), 60)
        XCTAssertEqual(ClockTools.parseUTCOffset("+05:30"), 330)
        XCTAssertEqual(ClockTools.parseUTCOffset("UTC-8"), -480)
        XCTAssertEqual(ClockTools.parseUTCOffset("UTC-14:00"), -840)
        XCTAssertNil(ClockTools.parseUTCOffset("UTC+14:01"))
        XCTAssertNil(ClockTools.parseUTCOffset("banana"))
    }

    func testPerRoutineTabs() {
        let routine = RoutineConfig(targetTab: 8, returnTab: nil)
        XCTAssertEqual(routine.targetTab, 8)
        XCTAssertNil(routine.returnTab)

        let routine2 = RoutineConfig(targetTab: 4, returnTab: 1)
        XCTAssertEqual(routine2.targetTab, 4)
        XCTAssertEqual(routine2.returnTab, 1)
    }

    func testShuffleSlotsPreservesSlots() throws {
        let areas = [0, 120, 240, 360].enumerated().map { index, sec in
            AreaConfig(name: "A\(index)", anchorSeconds: sec, orderMode: .shuffleSlots, randomGroup: "A")
        }
        let routine = RoutineConfig(repeatSeconds: 600, areas: areas)
        let plan = try CyclePlanner.plan(routine: routine, cycleIndex: 5)
        XCTAssertEqual(Set(plan.map { Int($0.offsetSeconds) }), Set([0, 120, 240, 360]))
        XCTAssertEqual(plan.count, 4)
    }

    func testRandomTimeSpacingAndBounds() throws {
        let start = AreaConfig(name: "Start", anchorSeconds: 0, jitterSeconds: 5, orderMode: .fixed)
        let stop = AreaConfig(name: "Stop", anchorSeconds: 540, jitterSeconds: 5, orderMode: .fixed)
        var mids: [AreaConfig] = []
        for i in 0..<8 {
            mids.append(AreaConfig(name: "R\(i)", anchorSeconds: 60 + i * 50, orderMode: .randomTime,
                                   randomGroup: "A", minimumSpacingSeconds: 10,
                                   randomPickMode: .range, randomPickMin: 4, randomPickMax: 8))
        }
        let routine = RoutineConfig(repeatSeconds: 600, areas: [start] + mids + [stop])
        for cycle in 0..<1000 {
            let plan = try CyclePlanner.plan(routine: routine, cycleIndex: cycle)
            let randomTimes = plan.filter { $0.areaName.hasPrefix("R") }.map(\.offsetSeconds).sorted()
            XCTAssertTrue((4...8).contains(randomTimes.count))
            for i in 1..<randomTimes.count {
                XCTAssertGreaterThanOrEqual(randomTimes[i] - randomTimes[i-1], 10.0 - 0.0001)
            }
            if let first = randomTimes.first { XCTAssertGreaterThanOrEqual(first, 15) }
            if let last = randomTimes.last { XCTAssertLessThanOrEqual(last, 525) }
        }
    }

    func testExactPickCount() throws {
        let start = AreaConfig(name: "Start", anchorSeconds: 0, orderMode: .fixed)
        let stop = AreaConfig(name: "Stop", anchorSeconds: 500, orderMode: .fixed)
        let mids = (0..<10).map { i in
            AreaConfig(name: "R\(i)", anchorSeconds: 20 + i * 40, orderMode: .randomTime,
                       randomGroup: "A", minimumSpacingSeconds: 5,
                       randomPickMode: .exact, randomPickMin: 4, randomPickMax: 4)
        }
        let routine = RoutineConfig(repeatSeconds: 600, areas: [start] + mids + [stop])
        for cycle in 0..<200 {
            let plan = try CyclePlanner.plan(routine: routine, cycleIndex: cycle)
            XCTAssertEqual(plan.filter { $0.areaName.hasPrefix("R") }.count, 4)
        }
    }
    func testRandomRangeUsesMultipleCounts() throws {
        let start = AreaConfig(name: "Start", anchorSeconds: 0, orderMode: .fixed)
        let stop = AreaConfig(name: "Stop", anchorSeconds: 580, orderMode: .fixed)
        let mids = (0..<10).map { i in
            AreaConfig(name: "R\(i)", anchorSeconds: 30 + i * 50, orderMode: .randomTime,
                       randomGroup: "A", minimumSpacingSeconds: 5,
                       randomPickMode: .range, randomPickMin: 4, randomPickMax: 10)
        }
        let routine = RoutineConfig(repeatSeconds: 600, areas: [start] + mids + [stop])
        var counts = Set<Int>()
        for cycle in 0..<5000 {
            let plan = try CyclePlanner.plan(routine: routine, cycleIndex: cycle)
            counts.insert(plan.filter { $0.areaName.hasPrefix("R") }.count)
        }
        XCTAssertEqual(counts, Set(4...10))
    }

    func testClockRoundTripsAcrossOffsets() {
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        for offset in stride(from: -840, through: 840, by: 15) {
            let display = ClockTools.displayDate(base, offsetMinutes: offset)
            XCTAssertEqual(ClockTools.utcDate(fromDisplay: display, offsetMinutes: offset), base)
        }
    }

    func testProfileJSONRoundTrip() throws {
        var profile = ProfileConfig(name: "Parity")
        profile.routines[0].targetTab = 5
        profile.routines[0].returnTab = nil
        profile.randomness = .preset(.high)
        profile.clockUTCOffsetMinutes = 60
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ProfileConfig.self, from: data)
        XCTAssertEqual(decoded.name, "Parity")
        XCTAssertEqual(decoded.routines[0].targetTab, 5)
        XCTAssertNil(decoded.routines[0].returnTab)
        XCTAssertEqual(decoded.randomness.profile, .high)
        XCTAssertEqual(decoded.clockUTCOffsetMinutes, 60)
    }

}
