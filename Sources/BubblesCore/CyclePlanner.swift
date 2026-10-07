import Foundation

public struct PlannedAction: Identifiable, Hashable, Sendable {
    public var id: UUID { areaID }
    public let routineID: UUID
    public let areaID: UUID
    public let areaName: String
    public let offsetSeconds: Double
    public let cycleIndex: Int

    public init(routineID: UUID, areaID: UUID, areaName: String, offsetSeconds: Double, cycleIndex: Int) {
        self.routineID = routineID
        self.areaID = areaID
        self.areaName = areaName
        self.offsetSeconds = offsetSeconds
        self.cycleIndex = cycleIndex
    }
}

public enum CyclePlannerError: Error, LocalizedError, Equatable {
    case invalidPeriod
    case anchorOutsidePeriod(String)
    case missingRandomTimeBoundary(String)
    case impossibleSpacing(String)
    case impossiblePickCount(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPeriod: return "Routine repeat period must be greater than zero."
        case .anchorOutsidePeriod(let name): return "Area '\(name)' is outside the routine period."
        case .missingRandomTimeBoundary(let name): return "Random Time area '\(name)' needs an enabled Fixed area before and after it."
        case .impossibleSpacing(let group): return "Random Time group \(group) cannot fit its minimum spacing inside the Fixed boundaries."
        case .impossiblePickCount(let group): return "Random Time group \(group) asks for more enabled candidates than are available."
        }
    }
}

public enum CyclePlanner {
    private struct WindowKey: Hashable {
        let group: String
        let beforeID: UUID
        let afterID: UUID
    }

    public static func validate(_ routine: RoutineConfig, randomTimeSpreadPercent: Int = 100) throws {
        guard routine.repeatSeconds > 0 else { throw CyclePlannerError.invalidPeriod }
        for area in routine.areas where area.enabled {
            if area.anchorSeconds >= routine.repeatSeconds {
                throw CyclePlannerError.anchorOutsidePeriod(area.name)
            }
        }
        _ = try plan(routine: routine, cycleIndex: 0, randomTimeSpreadPercent: randomTimeSpreadPercent)
    }

    public static func plan(routine: RoutineConfig, cycleIndex: Int, randomTimeSpreadPercent: Int = 100) throws -> [PlannedAction] {
        guard routine.repeatSeconds > 0 else { throw CyclePlannerError.invalidPeriod }
        let enabled = routine.areas.filter(\.enabled)
        for area in enabled where area.anchorSeconds >= routine.repeatSeconds {
            throw CyclePlannerError.anchorOutsidePeriod(area.name)
        }

        var result: [PlannedAction] = []
        var assigned: [UUID: Double] = [:]

        // Fixed areas keep their anchors.
        for area in enabled where area.orderMode == .fixed {
            assigned[area.id] = jittered(anchor: Double(area.anchorSeconds), jitter: area.jitterSeconds,
                                          seed: seed(routine, cycleIndex, area, "fixed"),
                                          period: routine.repeatSeconds)
        }

        // Shuffle Slots: shuffle members across their existing anchor slots by group.
        let shuffleGroups = Dictionary(grouping: enabled.filter { $0.orderMode == .shuffleSlots }, by: { $0.randomGroup })
        for (group, members) in shuffleGroups {
            let orderedMembers = members.sorted { $0.anchorSeconds < $1.anchorSeconds }
            let slots = orderedMembers.map { Double($0.anchorSeconds) }
            var rng = DeterministicRandom(seed: SeedMixer.mix(routine.shuffleSeed, UInt64(cycleIndex &+ 1), SeedMixer.hash("slots|\(group)")))
            let shuffled = rng.shuffled(orderedMembers)
            for (idx, member) in shuffled.enumerated() {
                assigned[member.id] = jittered(anchor: slots[idx], jitter: member.jitterSeconds,
                                               seed: seed(routine, cycleIndex, member, "slot-jitter"),
                                               period: routine.repeatSeconds)
            }
        }

        // Random Time areas are grouped by nearest Fixed boundaries + group.
        let fixedSorted = enabled.filter { $0.orderMode == .fixed }.sorted { $0.anchorSeconds < $1.anchorSeconds }
        var windows: [WindowKey: [AreaConfig]] = [:]
        for area in enabled where area.orderMode == .randomTime {
            guard let before = fixedSorted.last(where: { $0.anchorSeconds < area.anchorSeconds }),
                  let after = fixedSorted.first(where: { $0.anchorSeconds > area.anchorSeconds }) else {
                throw CyclePlannerError.missingRandomTimeBoundary(area.name)
            }
            let key = WindowKey(group: area.randomGroup, beforeID: before.id, afterID: after.id)
            windows[key, default: []].append(area)
        }

        for (key, candidates) in windows {
            guard let before = fixedSorted.first(where: { $0.id == key.beforeID }),
                  let after = fixedSorted.first(where: { $0.id == key.afterID }) else { continue }

            let policy = pickPolicy(candidates)
            let pickCount: Int
            switch policy.mode {
            case .all:
                pickCount = candidates.count
            case .exact:
                guard policy.min <= candidates.count else { throw CyclePlannerError.impossiblePickCount(key.group) }
                pickCount = policy.min
            case .range:
                guard policy.min <= candidates.count else { throw CyclePlannerError.impossiblePickCount(key.group) }
                var rng = DeterministicRandom(seed: SeedMixer.mix(routine.shuffleSeed, UInt64(cycleIndex &+ 1), SeedMixer.hash("pick|\(key.group)|\(before.id)|\(after.id)")))
                pickCount = rng.int(in: policy.min...min(policy.max, candidates.count))
            }

            var rng = DeterministicRandom(seed: SeedMixer.mix(routine.shuffleSeed, UInt64(cycleIndex &+ 1), SeedMixer.hash("members|\(key.group)|\(before.id)|\(after.id)")))
            let selected = Array(rng.shuffled(candidates).prefix(pickCount))
            guard !selected.isEmpty else { continue }

            let spacing = max(0, selected.map(\.minimumSpacingSeconds).max() ?? 0)
            let beforeJitter = before.jitterSeconds
            let afterJitter = after.jitterSeconds
            var safeLower = Double(before.anchorSeconds + beforeJitter + spacing)
            var safeUpper = Double(after.anchorSeconds - afterJitter - spacing)
            let required = Double(max(0, selected.count - 1) * spacing)
            guard safeUpper - safeLower >= required else { throw CyclePlannerError.impossibleSpacing(key.group) }

            // Random Time spread shrinks the usable extra range around the center.
            let spreadPercent = max(1, min(100, randomTimeSpreadPercent))
            let extra = max(0, (safeUpper - safeLower) - required)
            let reducedExtra = extra * Double(spreadPercent) / 100.0
            let inset = (extra - reducedExtra) / 2.0
            safeLower += inset
            safeUpper -= inset

            var timeRng = DeterministicRandom(seed: SeedMixer.mix(routine.shuffleSeed, UInt64(cycleIndex &+ 1), SeedMixer.hash("time|\(key.group)|\(before.id)|\(after.id)")))
            let remainingExtra = max(0, (safeUpper - safeLower) - required)
            var samples = (0..<selected.count).map { _ in timeRng.double(in: 0...remainingExtra) }.sorted()
            if samples.isEmpty { samples = [0] }
            let times = samples.enumerated().map { idx, extraValue in
                safeLower + extraValue + Double(idx * spacing)
            }
            let memberOrder = timeRng.shuffled(selected)
            for (idx, area) in memberOrder.enumerated() {
                assigned[area.id] = times[idx]
            }
        }

        for area in enabled {
            guard let offset = assigned[area.id] else { continue }
            result.append(PlannedAction(routineID: routine.id, areaID: area.id, areaName: area.name,
                                        offsetSeconds: min(Double(routine.repeatSeconds - 1), max(0, offset)), cycleIndex: cycleIndex))
        }

        return result.sorted {
            if $0.offsetSeconds == $1.offsetSeconds { return $0.areaName < $1.areaName }
            return $0.offsetSeconds < $1.offsetSeconds
        }
    }

    private static func pickPolicy(_ candidates: [AreaConfig]) -> (mode: RandomPickMode, min: Int, max: Int) {
        let counts = Dictionary(grouping: candidates, by: { $0.randomPickMode }).mapValues(\.count)
        let mode = counts.max(by: { $0.value < $1.value })?.key ?? .all
        let same = candidates.filter { $0.randomPickMode == mode }
        switch mode {
        case .all:
            return (.all, candidates.count, candidates.count)
        case .exact:
            let value = max(1, same.map(\.randomPickMin).filter { $0 > 0 }.first ?? 1)
            return (.exact, value, value)
        case .range:
            let lo = max(1, same.map(\.randomPickMin).filter { $0 > 0 }.first ?? 1)
            let hi = max(lo, same.map(\.randomPickMax).filter { $0 > 0 }.first ?? lo)
            return (.range, lo, hi)
        }
    }

    private static func seed(_ routine: RoutineConfig, _ cycle: Int, _ area: AreaConfig, _ label: String) -> UInt64 {
        SeedMixer.mix(routine.shuffleSeed, UInt64(cycle &+ 1), SeedMixer.hash(area.id.uuidString), SeedMixer.hash(label))
    }

    private static func jittered(anchor: Double, jitter: Int, seed: UInt64, period: Int) -> Double {
        guard jitter > 0 else { return anchor }
        var rng = DeterministicRandom(seed: seed)
        let delta = rng.int(in: (-jitter)...jitter)
        return min(Double(max(0, period - 1)), max(0, anchor + Double(delta)))
    }
}
