import Foundation

public enum AreaOrderMode: String, Codable, CaseIterable, Sendable {
    case fixed
    case shuffleSlots
    case randomTime

    public var displayName: String {
        switch self {
        case .fixed: return "Fixed"
        case .shuffleSlots: return "Shuffle Slots"
        case .randomTime: return "Random Time"
        }
    }
}

public enum RandomPickMode: String, Codable, CaseIterable, Sendable {
    case all
    case exact
    case range

    public var displayName: String {
        switch self {
        case .all: return "All"
        case .exact: return "Exact"
        case .range: return "Min-Max"
        }
    }
}

public enum AreaShape: String, Codable, CaseIterable, Sendable {
    case rectangle
    case square
}

public struct ClickRect: Codable, Hashable, Sendable {
    public var xMin: Double
    public var xMax: Double
    public var yMin: Double
    public var yMax: Double

    public init(xMin: Double = 2940, xMax: Double = 3080, yMin: Double = 990, yMax: Double = 1015) {
        self.xMin = min(xMin, xMax)
        self.xMax = max(xMin, xMax)
        self.yMin = min(yMin, yMax)
        self.yMax = max(yMin, yMax)
    }

    public var width: Double { max(0, xMax - xMin) }
    public var height: Double { max(0, yMax - yMin) }
    public var isValid: Bool { xMax >= xMin && yMax >= yMin }
}

public struct AreaConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var anchorSeconds: Int
    public var jitterSeconds: Int
    public var rect: ClickRect
    public var shape: AreaShape
    public var orderMode: AreaOrderMode
    public var randomGroup: String
    public var minimumSpacingSeconds: Int
    public var randomPickMode: RandomPickMode
    public var randomPickMin: Int
    public var randomPickMax: Int
    public var clickCount: Int
    public var lastClick: Date?

    public init(
        id: UUID = UUID(),
        name: String = "Area 1",
        enabled: Bool = true,
        anchorSeconds: Int = 0,
        jitterSeconds: Int = 0,
        rect: ClickRect = ClickRect(),
        shape: AreaShape = .rectangle,
        orderMode: AreaOrderMode = .fixed,
        randomGroup: String = "A",
        minimumSpacingSeconds: Int = 8,
        randomPickMode: RandomPickMode = .all,
        randomPickMin: Int = 0,
        randomPickMax: Int = 0,
        clickCount: Int = 0,
        lastClick: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.anchorSeconds = max(0, anchorSeconds)
        self.jitterSeconds = max(0, jitterSeconds)
        self.rect = rect
        self.shape = shape
        self.orderMode = orderMode
        self.randomGroup = randomGroup.isEmpty ? "A" : randomGroup
        self.minimumSpacingSeconds = max(0, minimumSpacingSeconds)
        self.randomPickMode = randomPickMode
        self.randomPickMin = max(0, randomPickMin)
        self.randomPickMax = max(0, randomPickMax)
        self.clickCount = max(0, clickCount)
        self.lastClick = lastClick
    }
}

public struct RoutineConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var repeatSeconds: Int
    public var startOffsetSeconds: Int
    public var startImmediately: Bool
    public var targetTab: Int
    public var returnTab: Int?
    public var shuffleSeed: UInt64
    public var areas: [AreaConfig]

    public init(
        id: UUID = UUID(),
        name: String = "Routine 1",
        enabled: Bool = true,
        repeatSeconds: Int = 600,
        startOffsetSeconds: Int = 0,
        startImmediately: Bool = true,
        targetTab: Int = 8,
        returnTab: Int? = nil,
        shuffleSeed: UInt64 = UInt64.random(in: 1...UInt64.max),
        areas: [AreaConfig] = [AreaConfig()]
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.repeatSeconds = max(1, repeatSeconds)
        self.startOffsetSeconds = max(0, startOffsetSeconds)
        self.startImmediately = startImmediately
        self.targetTab = min(9, max(1, targetTab))
        if let returnTab {
            self.returnTab = (1...9).contains(returnTab) ? returnTab : nil
        } else {
            self.returnTab = nil
        }
        self.shuffleSeed = shuffleSeed == 0 ? 1 : shuffleSeed
        self.areas = areas
    }
}

public enum RandomnessProfile: String, Codable, CaseIterable, Sendable {
    case low, medium, high, custom
}

public struct RandomnessSettings: Codable, Hashable, Sendable {
    public var profile: RandomnessProfile
    public var timingSpreadPercent: Int
    public var paceVariationPercent: Int
    public var coordinateSpreadPercent: Int
    public var randomTimeSpreadPercent: Int
    public var clickHoldMinMs: Int
    public var clickHoldMaxMs: Int

    public init(
        profile: RandomnessProfile = .medium,
        timingSpreadPercent: Int = 75,
        paceVariationPercent: Int = 15,
        coordinateSpreadPercent: Int = 75,
        randomTimeSpreadPercent: Int = 85,
        clickHoldMinMs: Int = 25,
        clickHoldMaxMs: Int = 90
    ) {
        self.profile = profile
        self.timingSpreadPercent = Self.clamp(timingSpreadPercent, 1, 100)
        self.paceVariationPercent = Self.clamp(paceVariationPercent, 0, 50)
        self.coordinateSpreadPercent = Self.clamp(coordinateSpreadPercent, 1, 100)
        self.randomTimeSpreadPercent = Self.clamp(randomTimeSpreadPercent, 1, 100)
        self.clickHoldMinMs = Self.clamp(clickHoldMinMs, 1, 1000)
        self.clickHoldMaxMs = Self.clamp(max(clickHoldMinMs, clickHoldMaxMs), 1, 1000)
    }

    public static func preset(_ profile: RandomnessProfile) -> RandomnessSettings {
        switch profile {
        case .low:
            return RandomnessSettings(profile: .low, timingSpreadPercent: 50, paceVariationPercent: 5, coordinateSpreadPercent: 45, randomTimeSpreadPercent: 60, clickHoldMinMs: 30, clickHoldMaxMs: 60)
        case .medium:
            return RandomnessSettings()
        case .high:
            return RandomnessSettings(profile: .high, timingSpreadPercent: 100, paceVariationPercent: 30, coordinateSpreadPercent: 100, randomTimeSpreadPercent: 100, clickHoldMinMs: 15, clickHoldMaxMs: 130)
        case .custom:
            return RandomnessSettings(profile: .custom)
        }
    }

    private static func clamp(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        min(hi, max(lo, value))
    }
}

public struct ReliabilitySettings: Codable, Hashable, Sendable {
    public var activationMinMs = 300
    public var activationMaxMs = 500
    public var tabSwitchMinMs = 250
    public var tabSwitchMaxMs = 450
    public var beforeClickMinMs = 175
    public var beforeClickMaxMs = 275
    public var afterClickMinMs = 100
    public var afterClickMaxMs = 200
    public var settleMinMs = 75
    public var settleMaxMs = 150
    public var mouseMoveMinMs = 300
    public var mouseMoveMaxMs = 600
    public var inputBusyWaitMs = 3000

    public init() {}
}

public struct ChromeWindowSelection: Codable, Hashable, Sendable {
    public var processID: Int32
    public var windowIndex: Int
    public var titleHint: String

    public init(processID: Int32 = 0, windowIndex: Int = 0, titleHint: String = "") {
        self.processID = processID
        self.windowIndex = windowIndex
        self.titleHint = titleHint
    }
}

public struct ProfileConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var chromeWindow: ChromeWindowSelection?
    public var routines: [RoutineConfig]
    public var randomness: RandomnessSettings
    public var reliability: ReliabilitySettings
    public var clockUTCOffsetMinutes: Int
    public var autoStart: AutoStartSettings
    public var autoStop: AutoStopSettings
    public var savedMonitorSignature: String

    public init(
        id: UUID = UUID(),
        name: String = "Default",
        chromeWindow: ChromeWindowSelection? = nil,
        routines: [RoutineConfig] = [RoutineConfig()],
        randomness: RandomnessSettings = RandomnessSettings(),
        reliability: ReliabilitySettings = ReliabilitySettings(),
        clockUTCOffsetMinutes: Int = 60,
        autoStart: AutoStartSettings = AutoStartSettings(),
        autoStop: AutoStopSettings = AutoStopSettings(),
        savedMonitorSignature: String = ""
    ) {
        self.id = id
        self.name = name
        self.chromeWindow = chromeWindow
        self.routines = routines
        self.randomness = randomness
        self.reliability = reliability
        self.clockUTCOffsetMinutes = min(840, max(-840, clockUTCOffsetMinutes))
        self.autoStart = autoStart
        self.autoStop = autoStop
        self.savedMonitorSignature = savedMonitorSignature
    }
}

public enum AutoTimerMode: String, Codable, CaseIterable, Sendable {
    case duration
    case clock
}

public enum AutoStopAction: String, Codable, CaseIterable, Sendable {
    case stop
    case exit
}

public struct AutoStartSettings: Codable, Hashable, Sendable {
    public var mode: AutoTimerMode = .duration
    public var durationSeconds: Int = 300
    public var clockDate: String = ""
    public var clockTime: String = ""
    public init() {}
}

public struct AutoStopSettings: Codable, Hashable, Sendable {
    public var mode: AutoTimerMode = .duration
    public var action: AutoStopAction = .stop
    public var durationSeconds: Int = 43_200
    public var clockDate: String = ""
    public var clockTime: String = ""
    public init() {}
}
