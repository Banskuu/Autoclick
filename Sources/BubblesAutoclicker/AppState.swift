#if os(macOS)
import AppKit
import Combine
import Foundation
import BubblesCore

@MainActor
final class AppState: ObservableObject {
    enum RunState: String { case stopped, running, paused }

    @Published var profiles: [ProfileSummary] = []
    @Published var activeProfileID: UUID?
    @Published var profile: ProfileConfig
    @Published var selectedRoutineID: UUID?
    @Published var selectedAreaID: UUID?
    @Published var runState: RunState = .stopped
    @Published var actionInProgress = false
    @Published var activityLog: [String] = []
    @Published var lastError = ""
    @Published var nextActionText = "-"
    @Published var currentClockText = ""
    @Published var chromeWindows: [MacChromeWindow] = []
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false
    @Published var emergencyState = false
    @Published var emergencyReason = ""
    @Published var settingsHotkeyPulse = 0

    @Published var autoStartArmed = false
    @Published var autoStartDeadline: Date?
    @Published var autoStopArmed = false
    @Published var autoStopDeadline: Date?
    @Published var autoStopWaitingForStart = false

    let repository = ProfileRepository()
    private let scheduler = SchedulerRuntime()
    private let automation = AutomationEngine()
    private let chrome = ChromeAXController()
    private let hotkeys = GlobalHotkeyMonitor()
    private var schedulerTimer: Timer?
    private var pausedAt: Date?
    private var executionTask: Task<Void, Never>?

    init() {
        let loaded = repository.loadRegistry()
        if loaded.profiles.isEmpty {
            let p = ProfileConfig()
            profile = p
            profiles = [ProfileSummary(id: p.id, name: p.name)]
            activeProfileID = p.id
            try? repository.saveProfile(p, makeBackup: false)
            try? repository.saveRegistry(profiles: profiles, active: p.id)
        } else {
            profiles = loaded.profiles
            let active = loaded.active ?? loaded.profiles.first!.id
            activeProfileID = active
            profile = repository.loadProfile(active) ?? ProfileConfig(id: active, name: loaded.profiles.first(where: { $0.id == active })?.name ?? "Default")
        }
        selectedRoutineID = profile.routines.first?.id
        selectedAreaID = profile.routines.first?.areas.first?.id
        refreshPermissions(prompt: false)
        refreshChromeWindows()
        currentClockText = clockText()
        if profile.savedMonitorSignature.isEmpty {
            profile.savedMonitorSignature = monitorSignature()
            saveProfile(makeBackup: false)
        }

        hotkeys.handler = { [weak self] code, modifiers in
            Task { @MainActor in
                guard let self else { return }
                switch code {
                case 100 where modifiers.contains(.control): self.startAll() // Ctrl+F8
                case 101: self.stopAll()       // F9
                case 109: NSApp.terminate(nil) // F10
                case 103:                      // F11
                    self.showMainWindow()
                    self.settingsHotkeyPulse += 1
                case 111: self.emergencyRelease(reason: "Manual F12") // F12
                default: break
                }
            }
        }
        hotkeys.start()
        automation.configureCallbacks(
            emergency: { [weak self] in self?.emergencyRelease(reason: "Protected-input emergency") },
            stop: { [weak self] in self?.stopAll() },
            quit: { NSApp.terminate(nil) }
        )
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        addLog("Bubbles macOS ready")
    }

    deinit {
        schedulerTimer?.invalidate()
        hotkeys.stop()
    }

    var selectedRoutineIndex: Int? { profile.routines.firstIndex { $0.id == selectedRoutineID } }
    var selectedRoutine: RoutineConfig? { selectedRoutineIndex.map { profile.routines[$0] } }
    var selectedAreaIndex: Int? {
        guard let ri = selectedRoutineIndex else { return nil }
        return profile.routines[ri].areas.firstIndex { $0.id == selectedAreaID }
    }
    var selectedArea: AreaConfig? {
        guard let ri = selectedRoutineIndex, let ai = selectedAreaIndex else { return nil }
        return profile.routines[ri].areas[ai]
    }

    func refreshPermissions(prompt: Bool) {
        accessibilityGranted = MacPermission.accessibility(prompt: prompt)
        inputMonitoringGranted = MacPermission.inputMonitoring(request: prompt)
    }

    func refreshChromeWindows() {
        chromeWindows = chrome.listWindows()
    }

    func selectChromeWindow(_ window: MacChromeWindow) {
        guard runState == .stopped else { return }
        profile.chromeWindow = chrome.selection(from: window)
        saveProfile()
        addLog("Chrome selected: \(window.displayName)")
    }

    func chromeStatus() -> String {
        guard let selection = profile.chromeWindow else { return "Not selected" }
        return chrome.verify(selection) ? "Ready" : "Unavailable - reselect Chrome"
    }

    func startAll() {
        if runState == .paused { resumeAll(); return }
        guard runState == .stopped else { return }
        disarmAutoStart(log: false)
        do {
            try validateStart()
            try scheduler.reset(profile: profile)
            runState = .running
            lastError = ""
            addLog("All routines started")
            if autoStopArmed && autoStopWaitingForStart {
                autoStopWaitingForStart = false
                autoStopDeadline = Date().addingTimeInterval(TimeInterval(profile.autoStop.durationSeconds))
                addLog("Auto Stop countdown started")
            }
        } catch {
            lastError = error.localizedDescription
            addLog("START BLOCKED - \(lastError)")
        }
    }

    func stopAll() {
        executionTask?.cancel()
        executionTask = nil
        Task { @MainActor in automation.requestAbort() }
        scheduler.clear()
        runState = .stopped
        actionInProgress = false
        pausedAt = nil
        disarmAutoStop(log: false)
        nextActionText = "-"
        addLog("All routines stopped")
    }

    func pauseAll() {
        guard runState == .running else { return }
        runState = .paused
        pausedAt = Date()
        addLog("Paused - routine timers frozen")
    }

    func resumeAll() {
        guard runState == .paused, let pausedAt else { return }
        scheduler.pauseShift(by: Date().timeIntervalSince(pausedAt))
        self.pausedAt = nil
        runState = .running
        addLog("Resumed")
    }

    func clickSelectedNow() {
        guard !actionInProgress, let routine = selectedRoutine, let area = selectedArea else { return }
        runManual(routine: routine, area: area)
    }

    func testAllAreasFast() {
        guard runState == .stopped, !actionInProgress, let routine = selectedRoutine else { return }
        let areas = routine.areas.filter(\.enabled)
        guard !areas.isEmpty else { return }
        actionInProgress = true
        executionTask = Task { [weak self] in
            guard let self else { return }
            for area in areas {
                if Task.isCancelled { break }
                do {
                    try await automation.perform(profile: profile, routine: routine, area: area)
                    await MainActor.run { self.recordSuccess(routineID: routine.id, areaID: area.id) }
                } catch {
                    await MainActor.run { self.addLog("Fast test \(area.name): \(error.localizedDescription)") }
                }
                try? await Task.sleep(for: .milliseconds(1500))
            }
            await MainActor.run { self.actionInProgress = false; self.executionTask = nil }
        }
    }

    func emergencyRelease(reason: String) {
        Task { @MainActor in automation.requestAbort() }
        emergencyState = true
        emergencyReason = "\(reason) at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))"
        addLog("WARNING - \(emergencyReason)")
    }

    func acknowledgeEmergency() {
        emergencyState = false; emergencyReason = ""
    }

    func tick() {
        currentClockText = clockText()
        tickAutoTimers()
        guard runState == .running else { updateNext(); return }
        guard !actionInProgress else { updateNext(); return }
        do {
            let skipped = try scheduler.tick(profile: profile)
            if skipped { addLog("Long system gap detected - missed schedules skipped") }
            if let due = scheduler.popDue() {
                runScheduled(due)
            }
        } catch {
            lastError = error.localizedDescription
            addLog("Scheduler error: \(lastError)")
            stopAll()
        }
        updateNext()
    }

    private func runScheduled(_ item: ScheduledClick) {
        guard let ri = profile.routines.firstIndex(where: { $0.id == item.routineID }),
              let ai = profile.routines[ri].areas.firstIndex(where: { $0.id == item.areaID }) else { return }
        let routine = profile.routines[ri]
        let area = profile.routines[ri].areas[ai]
        actionInProgress = true
        executionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await automation.perform(profile: profile, routine: routine, area: area)
                await MainActor.run {
                    self.recordSuccess(routineID: routine.id, areaID: area.id)
                    self.addLog("Clicked \(routine.name) -> \(area.name)")
                }
            } catch AutomationError.inputBusy {
                await MainActor.run {
                    self.scheduler.requeue(item, due: Date().addingTimeInterval(1))
                    self.addLog("\(routine.name) -> \(area.name): mouse busy, retrying")
                }
            } catch AutomationError.aborted {
                await MainActor.run { self.addLog("\(routine.name) -> \(area.name): aborted") }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.addLog("ERROR \(routine.name) -> \(area.name): \(error.localizedDescription)")
                }
            }
            await MainActor.run { self.actionInProgress = false; self.executionTask = nil; self.saveProfile(makeBackup: false) }
        }
    }

    private func runManual(routine: RoutineConfig, area: AreaConfig) {
        actionInProgress = true
        executionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await automation.perform(profile: profile, routine: routine, area: area)
                await MainActor.run { self.recordSuccess(routineID: routine.id, areaID: area.id); self.addLog("Manual click: \(routine.name) -> \(area.name)") }
            } catch { await MainActor.run { self.lastError = error.localizedDescription; self.addLog("Manual click error: \(error.localizedDescription)") } }
            await MainActor.run { self.actionInProgress = false; self.executionTask = nil }
        }
    }

    private func recordSuccess(routineID: UUID, areaID: UUID) {
        guard let ri = profile.routines.firstIndex(where: { $0.id == routineID }),
              let ai = profile.routines[ri].areas.firstIndex(where: { $0.id == areaID }) else { return }
        profile.routines[ri].areas[ai].clickCount += 1
        profile.routines[ri].areas[ai].lastClick = Date()
    }

    private func validateStart() throws {
        guard accessibilityGranted else { throw AppValidationError.accessibility }
        guard inputMonitoringGranted else { throw AppValidationError.inputMonitoring }
        guard chrome.verify(profile.chromeWindow) else { throw AppValidationError.chrome }
        guard profile.savedMonitorSignature == monitorSignature() else { throw AppValidationError.monitorLayout }
        guard profile.routines.contains(where: { $0.enabled && $0.areas.contains(where: \.enabled) }) else { throw AppValidationError.noActions }
        for routine in profile.routines where routine.enabled {
            guard (1...9).contains(routine.targetTab) else { throw AppValidationError.tabs(routine.name) }
            if let ret = routine.returnTab, !(1...9).contains(ret) { throw AppValidationError.tabs(routine.name) }
            try CyclePlanner.validate(routine, randomTimeSpreadPercent: profile.randomness.randomTimeSpreadPercent)
        }
    }

    private func updateNext() {
        guard let item = scheduler.next(), runState != .stopped else { nextActionText = "-"; return }
        let r = profile.routines.first(where: { $0.id == item.routineID })?.name ?? "Routine"
        let a = profile.routines.first(where: { $0.id == item.routineID })?.areas.first(where: { $0.id == item.areaID })?.name ?? "Area"
        let remaining = max(0, item.due.timeIntervalSince(Date()))
        nextActionText = "\(r) -> \(a) in \(formatDuration(remaining))"
    }

    func saveProfile(makeBackup: Bool = true) {
        do {
            try repository.saveProfile(profile, makeBackup: makeBackup)
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[idx].name = profile.name }
            try repository.saveRegistry(profiles: profiles, active: profile.id)
        } catch { lastError = "Save failed: \(error.localizedDescription)" }
    }

    func switchProfile(_ id: UUID) {
        guard runState == .stopped, !actionInProgress, id != activeProfileID else { return }
        saveProfile()
        guard let loaded = repository.loadProfile(id) else { return }
        profile = loaded
        activeProfileID = id
        selectedRoutineID = profile.routines.first?.id
        selectedAreaID = profile.routines.first?.areas.first?.id
        chromeWindows = chrome.listWindows()
        try? repository.saveRegistry(profiles: profiles, active: id)
        addLog("Profile loaded: \(profile.name)")
    }

    func createProfile(name: String) {
        guard runState == .stopped else { return }
        let p = ProfileConfig(name: name.isEmpty ? "New Profile" : name)
        profiles.append(ProfileSummary(id: p.id, name: p.name))
        try? repository.saveProfile(p, makeBackup: false)
        switchProfile(p.id)
    }

    func duplicateCurrentProfile() {
        guard runState == .stopped else { return }
        var p = profile
        p.id = UUID(); p.name += " Copy"; p.chromeWindow = nil
        profiles.append(ProfileSummary(id: p.id, name: p.name))
        try? repository.saveProfile(p, makeBackup: false)
        switchProfile(p.id)
    }

    func deleteCurrentProfile() {
        guard runState == .stopped, profiles.count > 1, let active = activeProfileID else { return }
        try? repository.deleteProfile(active)
        profiles.removeAll { $0.id == active }
        switchProfile(profiles[0].id)
    }

    func addRoutine() {
        guard runState == .stopped else { return }
        let r = RoutineConfig(name: "Routine \(profile.routines.count + 1)")
        profile.routines.append(r); selectedRoutineID = r.id; selectedAreaID = r.areas.first?.id; saveProfile()
    }

    func updateRoutine(_ routine: RoutineConfig) {
        guard runState == .stopped, let idx = profile.routines.firstIndex(where: { $0.id == routine.id }) else { return }
        profile.routines[idx] = routine; saveProfile()
    }

    func duplicateRoutine() {
        guard runState == .stopped, var r = selectedRoutine else { return }
        r.id = UUID(); r.name += " Copy"; r.areas = r.areas.map { area in var a = area; a.id = UUID(); return a }
        profile.routines.append(r); selectedRoutineID = r.id; selectedAreaID = r.areas.first?.id; saveProfile()
    }

    func removeRoutine() {
        guard runState == .stopped, let idx = selectedRoutineIndex, profile.routines.count > 1 else { return }
        profile.routines.remove(at: idx); selectedRoutineID = profile.routines.first?.id; selectedAreaID = profile.routines.first?.areas.first?.id; saveProfile()
    }

    func addArea() {
        guard runState == .stopped, let ri = selectedRoutineIndex else { return }
        let a = AreaConfig(name: "Area \(profile.routines[ri].areas.count + 1)")
        profile.routines[ri].areas.append(a); selectedAreaID = a.id; saveProfile()
    }

    func updateArea(_ area: AreaConfig) {
        guard runState == .stopped, let ri = selectedRoutineIndex,
              let ai = profile.routines[ri].areas.firstIndex(where: { $0.id == area.id }) else { return }
        profile.routines[ri].areas[ai] = area; saveProfile()
    }

    func duplicateArea() {
        guard runState == .stopped, let ri = selectedRoutineIndex, var a = selectedArea else { return }
        a.id = UUID(); a.name += " Copy"; a.clickCount = 0; a.lastClick = nil
        profile.routines[ri].areas.append(a); selectedAreaID = a.id; saveProfile()
    }

    func removeArea() {
        guard runState == .stopped, let ri = selectedRoutineIndex, let ai = selectedAreaIndex else { return }
        profile.routines[ri].areas.remove(at: ai); selectedAreaID = profile.routines[ri].areas.first?.id; saveProfile()
    }

    func applyRandomWindow(startAreaID: UUID, stopAreaID: UUID, spacingSeconds: Int, pickMode: RandomPickMode, min: Int, max: Int) {
        guard runState == .stopped, let ri = selectedRoutineIndex else { return }
        var routine = profile.routines[ri]
        let sorted = routine.areas.indices.sorted { routine.areas[$0].anchorSeconds < routine.areas[$1].anchorSeconds }
        guard let sp = sorted.firstIndex(where: { routine.areas[$0].id == startAreaID }),
              let ep = sorted.firstIndex(where: { routine.areas[$0].id == stopAreaID }), sp < ep else { return }
        let startIndex = sorted[sp], stopIndex = sorted[ep]
        routine.areas[startIndex].orderMode = .fixed
        routine.areas[stopIndex].orderMode = .fixed
        let middle = Array(sorted[(sp+1)..<ep])
        guard !middle.isEmpty else { return }
        let startSec = routine.areas[startIndex].anchorSeconds
        let stopSec = routine.areas[stopIndex].anchorSeconds
        for (pos, idx) in middle.enumerated() {
            routine.areas[idx].orderMode = .randomTime
            routine.areas[idx].randomGroup = "A"
            routine.areas[idx].minimumSpacingSeconds = spacingSeconds
            routine.areas[idx].randomPickMode = pickMode
            routine.areas[idx].randomPickMin = min
            routine.areas[idx].randomPickMax = max
            routine.areas[idx].anchorSeconds = startSec + ((stopSec - startSec) * (pos + 1) / (middle.count + 1))
        }
        profile.routines[ri] = routine; saveProfile()
    }

    func previewCycles(count: Int = 10) -> String {
        guard let routine = selectedRoutine else { return "No routine selected." }
        var lines: [String] = []
        for cycle in 0..<count {
            do {
                let plan = try CyclePlanner.plan(routine: routine, cycleIndex: cycle, randomTimeSpreadPercent: profile.randomness.randomTimeSpreadPercent)
                lines.append("Cycle \(cycle + 1):")
                for item in plan { lines.append("  \(formatSeconds(item.offsetSeconds))  \(item.areaName)") }
            } catch { lines.append("Cycle \(cycle + 1): ERROR \(error.localizedDescription)") }
        }
        return lines.joined(separator: "\n")
    }

    func armAutoStart() -> String? {
        guard runState == .stopped else { return "Stop Bubbles before arming Auto Start." }
        if profile.autoStart.mode == .duration {
            guard profile.autoStart.durationSeconds > 0 else { return "Auto Start duration must be greater than zero." }
            autoStartDeadline = Date().addingTimeInterval(TimeInterval(profile.autoStart.durationSeconds))
        } else {
            guard let date = ClockTools.parseDisplayDate(date: profile.autoStart.clockDate, time: profile.autoStart.clockTime,
                                                         offsetMinutes: profile.clockUTCOffsetMinutes), date > Date() else {
                return "Enter a valid future Auto Start clock date/time."
            }
            autoStartDeadline = date
        }
        autoStartArmed = true; saveProfile(); addLog("Auto Start armed")
        return nil
    }

    func disarmAutoStart(log: Bool = true) {
        if log && autoStartArmed { addLog("Auto Start disarmed") }
        autoStartArmed = false; autoStartDeadline = nil
    }

    func armAutoStop() -> String? {
        if profile.autoStop.mode == .duration {
            guard profile.autoStop.durationSeconds > 0 else { return "Auto Stop duration must be greater than zero." }
            autoStopArmed = true
            if runState == .running { autoStopDeadline = Date().addingTimeInterval(TimeInterval(profile.autoStop.durationSeconds)); autoStopWaitingForStart = false }
            else { autoStopDeadline = nil; autoStopWaitingForStart = true }
        } else {
            guard let date = ClockTools.parseDisplayDate(date: profile.autoStop.clockDate, time: profile.autoStop.clockTime,
                                                         offsetMinutes: profile.clockUTCOffsetMinutes), date > Date() else {
                return "Enter a valid future Auto Stop clock date/time."
            }
            autoStopArmed = true; autoStopWaitingForStart = false; autoStopDeadline = date
        }
        saveProfile(); addLog("Auto Stop armed")
        return nil
    }

    func disarmAutoStop(log: Bool = true) {
        if log && autoStopArmed { addLog("Auto Stop disarmed") }
        autoStopArmed = false; autoStopDeadline = nil; autoStopWaitingForStart = false
    }

    private func tickAutoTimers() {
        if autoStartArmed, let deadline = autoStartDeadline, Date() >= deadline {
            autoStartArmed = false; autoStartDeadline = nil; addLog("AUTO START triggered"); startAll()
        }
        if autoStopArmed, !autoStopWaitingForStart, let deadline = autoStopDeadline, Date() >= deadline {
            let action = profile.autoStop.action
            autoStopArmed = false; autoStopDeadline = nil; addLog("AUTO STOP triggered")
            stopAll()
            if action == .exit { NSApp.terminate(nil) }
        }
    }

    func timerStatus(start: Bool) -> String {
        let armed = start ? autoStartArmed : autoStopArmed
        if !armed { return start ? "Auto Start OFF" : "Auto Stop OFF" }
        if !start && autoStopWaitingForStart { return "Auto Stop waits for Start" }
        let deadline = start ? autoStartDeadline : autoStopDeadline
        guard let deadline else { return "Armed" }
        return "\(start ? "Auto Start" : "Auto Stop") \(formatDuration(max(0, deadline.timeIntervalSince(Date()))))"
    }

    func clockText() -> String {
        let display = ClockTools.displayDate(Date(), offsetMinutes: profile.clockUTCOffsetMinutes)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "HH:mm:ss"
        return "\(f.string(from: display)) \(ClockTools.formatUTCOffset(profile.clockUTCOffsetMinutes))"
    }

    func monitorSignature() -> String {
        NSScreen.screens.map { screen in
            let f = screen.frame
            return "\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height)),\(Int(screen.backingScaleFactor * 100))"
        }.sorted().joined(separator: "|")
    }

    func acceptCurrentMonitorLayout() {
        profile.savedMonitorSignature = monitorSignature()
        saveProfile()
        addLog("Current monitor layout accepted")
    }

    func restoreLatestBackup() -> String? {
        guard let latest = repository.listBackups(profileID: profile.id).first else { return "No backup exists for this profile." }
        do {
            var restored = try repository.restoreBackup(latest)
            restored.id = profile.id
            profile = restored
            selectedRoutineID = profile.routines.first?.id
            selectedAreaID = profile.routines.first?.areas.first?.id
            saveProfile(makeBackup: false)
            addLog("Restored latest profile backup")
            return nil
        } catch { return "Restore failed: \(error.localizedDescription)" }
    }

    func exportCurrentProfile() -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(profile.name).bubbles.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { try repository.exportProfile(profile, to: url); return nil }
        catch { return "Export failed: \(error.localizedDescription)" }
    }

    func importProfileFromPanel() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let imported = try repository.importProfile(from: url)
            profiles.append(ProfileSummary(id: imported.id, name: imported.name))
            try repository.saveRegistry(profiles: profiles, active: imported.id)
            switchProfile(imported.id)
            return nil
        } catch { return "Import failed: \(error.localizedDescription)" }
    }

    func diagnostics() -> String {
        let screens = NSScreen.screens.map { screen in
            let f = screen.frame; return "\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height)) @\(Int(screen.backingScaleFactor))x"
        }.joined(separator: " | ")
        return """
        Bubbles Autoclicker macOS 0.1
        Profile: \(profile.name)
        State: \(runState.rawValue) | Action in progress: \(actionInProgress)
        Accessibility: \(accessibilityGranted ? "YES" : "NO")
        Input Monitoring: \(inputMonitoringGranted ? "YES" : "NO")
        Chrome: \(chromeStatus())
        Clock: \(clockText())
        Auto Start: \(timerStatus(start: true))
        Auto Stop: \(timerStatus(start: false))
        Emergency: \(emergencyState ? emergencyReason : "clear")
        Next: \(nextActionText)
        Screens: \(screens)
        Monitor layout: \(profile.savedMonitorSignature == monitorSignature() ? "matches saved" : "CHANGED")
        Last error: \(lastError.isEmpty ? "-" : lastError)
        Config: \(repository.rootURL.path)
        """
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Bubbles Autoclicker" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func addLog(_ message: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        activityLog.append("[\(f.string(from: Date()))] \(message)")
        if activityLog.count > 200 { activityLog.removeFirst(activityLog.count - 200) }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "+%02d:%02d", total / 60, total % 60)
    }
}

enum AppValidationError: LocalizedError {
    case accessibility, inputMonitoring, chrome, monitorLayout, noActions, tabs(String)
    var errorDescription: String? {
        switch self {
        case .accessibility: return "Grant Accessibility permission in System Settings."
        case .inputMonitoring: return "Grant Input Monitoring permission in System Settings."
        case .chrome: return "Select a currently-open Chrome window."
        case .monitorLayout: return "Monitor layout changed. Open Settings and accept the current monitor layout before starting."
        case .noActions: return "Enable at least one routine and one area."
        case .tabs(let name): return "Routine '\(name)' has an invalid Target/Return tab."
        }
    }
}
#endif
