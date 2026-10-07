#if os(macOS)
import Foundation
import BubblesCore

struct ScheduledClick: Identifiable, Hashable {
    let id = UUID()
    let routineID: UUID
    let areaID: UUID
    let cycleIndex: Int
    var due: Date
}

struct RoutineRuntime {
    var nextCycleBase: Date
    var nextCycleIndex: Int
}

final class SchedulerRuntime {
    private(set) var queue: [ScheduledClick] = []
    private(set) var routines: [UUID: RoutineRuntime] = [:]
    private(set) var lastHeartbeat = Date()

    func reset(profile: ProfileConfig, now: Date = Date()) throws {
        queue.removeAll()
        routines.removeAll()
        lastHeartbeat = now
        for routine in profile.routines where routine.enabled {
            try CyclePlanner.validate(routine, randomTimeSpreadPercent: profile.randomness.randomTimeSpreadPercent)
            let firstBase = now.addingTimeInterval(TimeInterval(routine.startOffsetSeconds + (routine.startImmediately ? 0 : routine.repeatSeconds)))
            try enqueueCycle(routine: routine, cycleIndex: 0, base: firstBase, spread: profile.randomness.randomTimeSpreadPercent)
            routines[routine.id] = RoutineRuntime(nextCycleBase: firstBase.addingTimeInterval(TimeInterval(routine.repeatSeconds)), nextCycleIndex: 1)
        }
        sortQueue()
    }

    func tick(profile: ProfileConfig, now: Date = Date()) throws -> Bool {
        let gap = now.timeIntervalSince(lastHeartbeat)
        lastHeartbeat = now
        var skippedWakeGap = false
        if gap >= 15 {
            skippedWakeGap = true
            queue.removeAll { $0.due <= now }
            for routine in profile.routines where routine.enabled {
                guard var runtime = routines[routine.id] else { continue }
                while runtime.nextCycleBase <= now {
                    runtime.nextCycleBase = runtime.nextCycleBase.addingTimeInterval(TimeInterval(routine.repeatSeconds))
                    runtime.nextCycleIndex += 1
                }
                routines[routine.id] = runtime
            }
        }

        let horizon = now.addingTimeInterval(5)
        for routine in profile.routines where routine.enabled {
            guard var runtime = routines[routine.id] else { continue }
            while runtime.nextCycleBase <= horizon {
                try enqueueCycle(routine: routine, cycleIndex: runtime.nextCycleIndex, base: runtime.nextCycleBase,
                                 spread: profile.randomness.randomTimeSpreadPercent)
                runtime.nextCycleBase = runtime.nextCycleBase.addingTimeInterval(TimeInterval(routine.repeatSeconds))
                runtime.nextCycleIndex += 1
            }
            routines[routine.id] = runtime
        }
        sortQueue()
        return skippedWakeGap
    }

    func popDue(now: Date = Date()) -> ScheduledClick? {
        guard let first = queue.first, first.due <= now else { return nil }
        queue.removeFirst()
        return first
    }

    func next() -> ScheduledClick? { queue.first }

    func requeue(_ item: ScheduledClick, due: Date) {
        var copy = item
        copy.due = due
        queue.append(copy)
        sortQueue()
    }

    func pauseShift(by interval: TimeInterval) {
        for i in queue.indices { queue[i].due = queue[i].due.addingTimeInterval(interval) }
        for key in routines.keys {
            routines[key]?.nextCycleBase = routines[key]!.nextCycleBase.addingTimeInterval(interval)
        }
    }

    func clear() {
        queue.removeAll(); routines.removeAll(); lastHeartbeat = Date()
    }

    private func enqueueCycle(routine: RoutineConfig, cycleIndex: Int, base: Date, spread: Int) throws {
        let plan = try CyclePlanner.plan(routine: routine, cycleIndex: cycleIndex, randomTimeSpreadPercent: spread)
        for item in plan {
            queue.append(ScheduledClick(routineID: routine.id, areaID: item.areaID, cycleIndex: cycleIndex,
                                        due: base.addingTimeInterval(item.offsetSeconds)))
        }
    }

    private func sortQueue() {
        queue.sort { a, b in a.due == b.due ? a.id.uuidString < b.id.uuidString : a.due < b.due }
    }
}
#endif
