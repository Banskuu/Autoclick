#if os(macOS)
import AppKit
import ApplicationServices
import Foundation
import BubblesCore

struct MacChromeWindow: Identifiable, Hashable {
    let id: String
    let processID: pid_t
    let index: Int
    let title: String

    var displayName: String {
        title.isEmpty ? "Chrome window \(index + 1)" : "\(index + 1): \(title)"
    }
}

enum MacPermission {
    static func accessibility(prompt: Bool = false) -> Bool {
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        return AXIsProcessTrusted()
    }

    static func inputMonitoring(request: Bool = false) -> Bool {
        if request { return CGRequestListenEventAccess() }
        return CGPreflightListenEventAccess()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class ChromeAXController {
    static let bundleIdentifier = "com.google.Chrome"

    func listWindows() -> [MacChromeWindow] {
        guard MacPermission.accessibility(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else { return [] }
        let appAX = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows: [AXUIElement] = attribute(appAX, kAXWindowsAttribute as CFString) else { return [] }
        return windows.enumerated().map { index, window in
            let title: String = attribute(window, kAXTitleAttribute as CFString) ?? ""
            return MacChromeWindow(id: "\(app.processIdentifier):\(index):\(title)", processID: app.processIdentifier,
                                   index: index, title: title)
        }
    }

    func selection(from window: MacChromeWindow) -> ChromeWindowSelection {
        ChromeWindowSelection(processID: window.processID, windowIndex: window.index, titleHint: window.title)
    }

    func verify(_ selection: ChromeWindowSelection?) -> Bool {
        guard let selection else { return false }
        return resolve(selection) != nil
    }

    func activate(_ selection: ChromeWindowSelection) -> Bool {
        guard let (app, window) = resolve(selection) else { return false }
        app.activate(options: [.activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }

    func isFrontmost(_ selection: ChromeWindowSelection) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        guard front.processIdentifier == selection.processID else { return false }
        guard let (_, selectedWindow) = resolve(selection) else { return false }
        let appAX = AXUIElementCreateApplication(selection.processID)
        guard let focused: AXUIElement = attribute(appAX, kAXFocusedWindowAttribute as CFString) else { return false }
        return CFEqual(focused, selectedWindow)
    }

    private func resolve(_ selection: ChromeWindowSelection) -> (NSRunningApplication, AXUIElement)? {
        guard let app = NSRunningApplication(processIdentifier: selection.processID), !app.isTerminated else { return nil }
        let appAX = AXUIElementCreateApplication(selection.processID)
        guard let windows: [AXUIElement] = attribute(appAX, kAXWindowsAttribute as CFString), !windows.isEmpty else { return nil }

        if windows.indices.contains(selection.windowIndex) {
            let candidate = windows[selection.windowIndex]
            let title: String = attribute(candidate, kAXTitleAttribute as CFString) ?? ""
            if selection.titleHint.isEmpty || title == selection.titleHint { return (app, candidate) }
        }
        if !selection.titleHint.isEmpty,
           let candidate = windows.first(where: { (attribute($0, kAXTitleAttribute as CFString) as String? ?? "") == selection.titleHint }) {
            return (app, candidate)
        }
        return nil
    }

    private func attribute<T>(_ element: AXUIElement, _ key: CFString) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key, &value)
        guard result == .success else { return nil }
        return value as? T
    }
}

private let bubblesSyntheticMarker: Int64 = 0x00425542424C4553 // "BUBBLES"

final class InputBlocker {
    var emergencyHandler: (() -> Void)?
    var stopHandler: (() -> Void)?
    var quitHandler: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var isBlocking = false

    func start() -> Bool {
        guard !isBlocking else { return true }
        guard MacPermission.accessibility(), MacPermission.inputMonitoring() else { return false }

        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel
        ]
        var mask: CGEventMask = 0
        for type in types { mask |= CGEventMask(1) << CGEventMask(type.rawValue) }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                             place: .headInsertEventTap,
                                             options: .defaultTap,
                                             eventsOfInterest: mask,
                                             callback: bubblesInputTapCallback,
                                             userInfo: pointer) else { return false }
        let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        source = runSource
        isBlocking = true
        return true
    }

    func stop() {
        guard isBlocking else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        self.tap = nil
        self.source = nil
        isBlocking = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == bubblesSyntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 111 { // F12
                DispatchQueue.main.async { [weak self] in self?.emergencyHandler?() }
                return nil
            }
            if keyCode == 101 { // F9
                DispatchQueue.main.async { [weak self] in self?.stopHandler?() }
                return nil
            }
            if keyCode == 109 { // F10
                DispatchQueue.main.async { [weak self] in self?.quitHandler?() }
                return nil
            }
        }
        return nil
    }
}

private func bubblesInputTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                     userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let blocker = Unmanaged<InputBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    return blocker.handle(type: type, event: event)
}

struct FrontContext {
    let application: NSRunningApplication?
    let focusedWindow: AXUIElement?
    let mousePosition: CGPoint
}

@MainActor
final class AutomationEngine {
    private let chrome = ChromeAXController()
    private let blocker = InputBlocker()
    private var abortRequested = false

    init() {}

    func configureCallbacks(emergency: @escaping () -> Void, stop: @escaping () -> Void, quit: @escaping () -> Void) {
        blocker.emergencyHandler = emergency
        blocker.stopHandler = stop
        blocker.quitHandler = quit
    }

    func requestAbort() {
        abortRequested = true
        blocker.stop()
        releaseSyntheticLeftButton()
    }

    func perform(profile: ProfileConfig, routine: RoutineConfig, area: AreaConfig) async throws {
        abortRequested = false
        guard let selection = profile.chromeWindow else { throw AutomationError.chromeNotSelected }
        guard chrome.verify(selection) else { throw AutomationError.chromeUnavailable }
        try await waitForPhysicalMouseRelease(timeoutMs: profile.reliability.inputBusyWaitMs)

        let context = captureFrontContext()
        let paceFactor = randomPaceFactor(profile.randomness)
        let watchdogMs = watchdogDuration(profile)
        var watchdog: Task<Void, Never>?

        let blocked = await MainActor.run { blocker.start() }
        guard blocked else { throw AutomationError.inputProtectionUnavailable }
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(watchdogMs))
            guard !Task.isCancelled else { return }
            self?.requestAbort()
        }

        defer {
            watchdog?.cancel()
            blocker.stop()
            releaseSyntheticLeftButton()
            restore(context)
        }

        guard chrome.activate(selection) else { throw AutomationError.chromeUnavailable }
        try await delay(profile.reliability.activationMinMs, profile.reliability.activationMaxMs,
                        settings: profile.randomness, pace: paceFactor)
        try checkAbort()

        postCommandDigit(routine.targetTab)
        try await delay(profile.reliability.tabSwitchMinMs, profile.reliability.tabSwitchMaxMs,
                        settings: profile.randomness, pace: paceFactor)

        let target = randomPoint(in: area.rect, spreadPercent: profile.randomness.coordinateSpreadPercent)
        let original = context.mousePosition
        try await delay(profile.reliability.settleMinMs, profile.reliability.settleMaxMs,
                        settings: profile.randomness, pace: paceFactor)
        try await moveMouse(to: target, durationMs: variableDelay(profile.reliability.mouseMoveMinMs,
                                                                   profile.reliability.mouseMoveMaxMs,
                                                                   profile.randomness, paceFactor))
        try await delay(profile.reliability.beforeClickMinMs, profile.reliability.beforeClickMaxMs,
                        settings: profile.randomness, pace: paceFactor)
        try checkAbort()
        guard chrome.isFrontmost(selection) else { throw AutomationError.chromeLostFocus }

        let hold = balancedInt(profile.randomness.clickHoldMinMs...profile.randomness.clickHoldMaxMs)
        postMouse(.leftMouseDown, at: target)
        do {
            try await interruptibleSleep(ms: hold)
        } catch {
            postMouse(.leftMouseUp, at: target)
            throw error
        }
        postMouse(.leftMouseUp, at: target)
        try await delay(profile.reliability.afterClickMinMs, profile.reliability.afterClickMaxMs,
                        settings: profile.randomness, pace: paceFactor)
        try await moveMouse(to: original, durationMs: variableDelay(profile.reliability.mouseMoveMinMs,
                                                                     profile.reliability.mouseMoveMaxMs,
                                                                     profile.randomness, paceFactor))
        try await delay(profile.reliability.settleMinMs, profile.reliability.settleMaxMs,
                        settings: profile.randomness, pace: paceFactor)

        if let returnTab = routine.returnTab, returnTab != routine.targetTab {
            guard chrome.isFrontmost(selection) else { throw AutomationError.chromeLostFocus }
            postCommandDigit(returnTab)
            try await delay(profile.reliability.tabSwitchMinMs, profile.reliability.tabSwitchMaxMs,
                            settings: profile.randomness, pace: paceFactor)
        }
    }

    private func captureFrontContext() -> FrontContext {
        let app = NSWorkspace.shared.frontmostApplication
        var focused: AXUIElement?
        if let app {
            let appAX = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appAX, kAXFocusedWindowAttribute as CFString, &value) == .success {
                focused = (value as! AXUIElement)
            }
        }
        return FrontContext(application: app, focusedWindow: focused, mousePosition: CGEvent(source: nil)?.location ?? .zero)
    }

    private func restore(_ context: FrontContext) {
        if let app = context.application, !app.isTerminated {
            app.activate(options: [.activateIgnoringOtherApps])
            if let window = context.focusedWindow { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
        }
    }

    private func waitForPhysicalMouseRelease(timeoutMs: Int) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        var quietStart: Date?
        while Date() < deadline {
            let held = CGEventSource.buttonState(.combinedSessionState, button: .left)
                || CGEventSource.buttonState(.combinedSessionState, button: .right)
                || CGEventSource.buttonState(.combinedSessionState, button: .center)
            if held { quietStart = nil }
            else if quietStart == nil { quietStart = Date() }
            else if Date().timeIntervalSince(quietStart!) >= 0.06 { return }
            try await Task.sleep(for: .milliseconds(15))
        }
        throw AutomationError.inputBusy
    }

    private func postCommandDigit(_ tab: Int) {
        let map: [Int: CGKeyCode] = [1:18, 2:19, 3:20, 4:21, 5:23, 6:22, 7:26, 8:28, 9:25]
        guard let key = map[tab], let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)!
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)!
        down.flags = .maskCommand; up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: bubblesSyntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: bubblesSyntheticMarker)
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: bubblesSyntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    private func releaseSyntheticLeftButton() {
        let point = CGEvent(source: nil)?.location ?? .zero
        postMouse(.leftMouseUp, at: point)
    }

    private func moveMouse(to target: CGPoint, durationMs: Int) async throws {
        let start = CGEvent(source: nil)?.location ?? target
        let steps = max(1, durationMs / 10)
        for i in 1...steps {
            try checkAbort()
            let t = Double(i) / Double(steps)
            let point = CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: bubblesSyntheticMarker)
            event.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func randomPoint(in rect: ClickRect, spreadPercent: Int) -> CGPoint {
        func one(_ lo: Double, _ hi: Double) -> Double {
            guard hi > lo else { return lo }
            let center = (lo + hi) / 2
            let half = (hi - lo) / 2 * Double(max(1, min(100, spreadPercent))) / 100
            return Double.random(in: (center - half)...(center + half))
        }
        return CGPoint(x: one(rect.xMin, rect.xMax), y: one(rect.yMin, rect.yMax))
    }

    private func randomPaceFactor(_ settings: RandomnessSettings) -> Double {
        guard settings.paceVariationPercent > 0 else { return 1 }
        let a = Int.random(in: 0...settings.paceVariationPercent)
        let b = Int.random(in: 0...settings.paceVariationPercent)
        return 1 + Double((a + b) / 2) / 100
    }

    private func balancedInt(_ range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        return (Int.random(in: range) + Int.random(in: range)) / 2
    }

    private func variableDelay(_ minMs: Int, _ maxMs: Int, _ settings: RandomnessSettings, _ pace: Double) -> Int {
        let lo = min(minMs, maxMs), hi = max(minMs, maxMs)
        if lo == hi { return Int(Double(lo) * pace) }
        let center = Double(lo + hi) / 2
        let half = Double(hi - lo) / 2 * Double(settings.timingSpreadPercent) / 100
        let lower = max(0, Int(ceil(center - half)))
        let upper = max(lower, Int(floor(center + half)))
        return max(0, Int(Double(balancedInt(lower...upper)) * pace))
    }

    private func delay(_ lo: Int, _ hi: Int, settings: RandomnessSettings, pace: Double) async throws {
        try await interruptibleSleep(ms: variableDelay(lo, hi, settings, pace))
    }

    private func interruptibleSleep(ms: Int) async throws {
        var remaining = max(0, ms)
        while remaining > 0 {
            try checkAbort()
            let chunk = min(10, remaining)
            try await Task.sleep(for: .milliseconds(chunk))
            remaining -= chunk
        }
        try checkAbort()
    }

    private func checkAbort() throws {
        if abortRequested || Task.isCancelled { throw AutomationError.aborted }
    }

    private func watchdogDuration(_ profile: ProfileConfig) -> Int {
        let r = profile.reliability
        let expected = r.activationMaxMs + r.tabSwitchMaxMs * 2 + r.beforeClickMaxMs + r.afterClickMaxMs
            + r.settleMaxMs * 2 + r.mouseMoveMaxMs * 2 + profile.randomness.clickHoldMaxMs + 2500
        return max(12_000, expected + 8_000)
    }
}

enum AutomationError: LocalizedError {
    case chromeNotSelected, chromeUnavailable, chromeLostFocus, inputBusy, inputProtectionUnavailable, aborted
    var errorDescription: String? {
        switch self {
        case .chromeNotSelected: return "No Chrome window is selected."
        case .chromeUnavailable: return "The selected Chrome window is unavailable."
        case .chromeLostFocus: return "Chrome lost focus before the click."
        case .inputBusy: return "A physical mouse button stayed held too long."
        case .inputProtectionUnavailable: return "macOS Accessibility/Input Monitoring permission is required for protected input."
        case .aborted: return "Action aborted."
        }
    }
}

final class GlobalHotkeyMonitor {
    private var global: Any?
    private var local: Any?
    var handler: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    func start() {
        guard global == nil else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event); return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 100 || event.keyCode == 101 || event.keyCode == 109 || event.keyCode == 103 || event.keyCode == 111 {
            handler?(event.keyCode, event.modifierFlags)
        }
    }
}
#endif
