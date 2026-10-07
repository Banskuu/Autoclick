#if os(macOS)
import AppKit
import SwiftUI
import BubblesCore

struct MainView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var routineDraft: RoutineConfig?
    @State private var areaDraft: AreaConfig?
    @State private var showSettings = false
    @State private var showTimers = false
    @State private var timerStartTab = true
    @State private var showDiagnostics = false
    @State private var showPreview = false
    @State private var showRandomWindow = false
    @State private var showProfileManager = false

    var body: some View {
        VStack(spacing: 8) {
            header
            statusBar
            toolbar
            HSplitView {
                routinePane.frame(minWidth: 330)
                areaPane.frame(minWidth: 480)
            }
            logPane.frame(minHeight: 100, idealHeight: 135, maxHeight: 180)
        }
        .padding(12)
        .sheet(item: $routineDraft) { RoutineEditorView(draft: $0) { app.updateRoutine($0) } }
        .sheet(item: $areaDraft) { AreaEditorView(draft: $0) { app.updateArea($0) } }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(app) }
        .sheet(isPresented: $showTimers) { AutoTimerView(initialStartTab: timerStartTab).environmentObject(app) }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView().environmentObject(app) }
        .sheet(isPresented: $showPreview) { PreviewView(text: app.previewCycles()) }
        .sheet(isPresented: $showRandomWindow) { RandomWindowView().environmentObject(app) }
        .sheet(isPresented: $showProfileManager) { ProfileManagerView().environmentObject(app) }
        .onAppear { app.refreshPermissions(prompt: false); app.refreshChromeWindows() }
        .onChange(of: app.settingsHotkeyPulse) { _ in showSettings = true }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bubbles Autoclicker").font(.title2.bold())
                Text("macOS native preview • \(app.currentClockText)").foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Profile", selection: Binding(get: { app.activeProfileID ?? app.profile.id }, set: { app.switchProfile($0) })) {
                ForEach(app.profiles) { Text($0.name).tag($0.id) }
            }.frame(width: 220)
            Button("Profiles…") { showProfileManager = true }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            Label(statusText, systemImage: statusIcon).font(.headline)
            Text("Chrome: \(app.chromeStatus())")
            Text("Next: \(app.nextActionText)").lineLimit(1)
            Spacer()
            if app.emergencyState { Button("Acknowledge Emergency") { app.acknowledgeEmergency() }.tint(.red) }
        }
        .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Start All") { app.startAll() }.keyboardShortcut(.init("8"), modifiers: [.control])
                Button(app.runState == .paused ? "Resume" : "Pause") { app.runState == .paused ? app.resumeAll() : app.pauseAll() }
                Button("Stop All") { app.stopAll() }
                Button("Click Selected Now") { app.clickSelectedNow() }
                Button("Chrome / Settings") { showSettings = true }
                Spacer()
            }
            HStack {
                Button(app.timerStatus(start: true)) { timerStartTab = true; showTimers = true }
                Button(app.timerStatus(start: false)) { timerStartTab = false; showTimers = true }
                Button("Diagnostics") { showDiagnostics = true }
                Button("Mini") { openWindow(id: "mini"); NSApp.keyWindow?.orderOut(nil) }
                Button("To Menu Bar") { NSApp.keyWindow?.orderOut(nil) }
                Spacer()
            }
        }
        .disabled(app.actionInProgress)
    }

    private var routinePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Routines").font(.headline)
            List(selection: $app.selectedRoutineID) {
                ForEach(app.profile.routines) { routine in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(routine.name).fontWeight(.semibold); if !routine.enabled { Text("OFF").foregroundStyle(.secondary) } }
                        Text("Every \(duration(routine.repeatSeconds)) • Start +\(duration(routine.startOffsetSeconds))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Chrome tab \(routine.targetTab) → \(routine.returnTab.map(String.init) ?? "Stay")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.tag(routine.id)
                }
            }
            .onChange(of: app.selectedRoutineID) { _ in app.selectedAreaID = app.selectedRoutine?.areas.first?.id }
            HStack {
                Button("+ Routine") { app.addRoutine(); routineDraft = app.selectedRoutine }
                Button("Edit") { routineDraft = app.selectedRoutine }.disabled(app.selectedRoutine == nil)
                Button("Copy") { app.duplicateRoutine() }
                Button("Remove") { app.removeRoutine() }
            }.disabled(app.runState != .stopped)
            HStack {
                Button("Preview 10 Cycles") { showPreview = true }
                Button("Test Routine Fast") { app.testAllAreasFast() }
            }
        }.padding(8)
    }

    private var areaPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Areas in \(app.selectedRoutine?.name ?? "-")").font(.headline)
            List(selection: $app.selectedAreaID) {
                ForEach(app.selectedRoutine?.areas ?? []) { area in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(area.name).fontWeight(.semibold)
                            Text("At +\(duration(area.anchorSeconds)) ±\(area.jitterSeconds)s • \(area.orderMode.displayName) \(area.randomGroup)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(area.clickCount) clicks").font(.caption2).foregroundStyle(.secondary)
                    }.tag(area.id)
                }
            }
            HStack {
                Button("+ Area") { app.addArea(); areaDraft = app.selectedArea }
                Button("Edit") { areaDraft = app.selectedArea }.disabled(app.selectedArea == nil)
                Button("Copy") { app.duplicateArea() }
                Button("Remove") { app.removeArea() }
                Button("Random Window…") { showRandomWindow = true }.disabled((app.selectedRoutine?.areas.count ?? 0) < 3)
            }.disabled(app.runState != .stopped)
        }.padding(8)
    }

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text("Recent Activity").font(.headline); Spacer(); Button("Clear") { app.activityLog.removeAll() } }
            ScrollView { LazyVStack(alignment: .leading) { ForEach(Array(app.activityLog.enumerated()), id: \.offset) { _, line in Text(line).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) } } }
                .padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var statusText: String {
        if app.emergencyState { return "EMERGENCY RELEASE" }
        if !app.lastError.isEmpty { return "ERROR" }
        if app.actionInProgress { return "RUNNING — clicking now" }
        return app.runState.rawValue.uppercased()
    }
    private var statusIcon: String { app.runState == .running ? "play.circle.fill" : (app.runState == .paused ? "pause.circle.fill" : "stop.circle") }
    private func duration(_ s: Int) -> String { String(format: "%02d:%02d", s/60, s%60) }
}

struct RoutineEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State var draft: RoutineConfig
    @State private var returnValue: Int
    let onSave: (RoutineConfig) -> Void

    init(draft: RoutineConfig, onSave: @escaping (RoutineConfig) -> Void) {
        _draft = State(initialValue: draft); _returnValue = State(initialValue: draft.returnTab ?? 0); self.onSave = onSave
    }

    var body: some View {
        Form {
            TextField("Name", text: $draft.name)
            Toggle("Enabled", isOn: $draft.enabled)
            HStack { Text("Repeat every (sec)"); TextField("Seconds", value: $draft.repeatSeconds, format: .number).frame(width: 100) }
            HStack { Text("Start offset (sec)"); TextField("Seconds", value: $draft.startOffsetSeconds, format: .number).frame(width: 100) }
            Toggle("First cycle immediately after offset", isOn: $draft.startImmediately)
            Picker("Target Chrome tab", selection: $draft.targetTab) { ForEach(1...9, id: \.self) { Text("\($0)").tag($0) } }
            Picker("Return tab", selection: $returnValue) {
                Text("None — stay on target").tag(0)
                ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { draft.repeatSeconds = max(1,draft.repeatSeconds); draft.startOffsetSeconds = max(0,draft.startOffsetSeconds); draft.returnTab = returnValue == 0 ? nil : returnValue; onSave(draft); dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 460)
    }
}

struct AreaEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State var draft: AreaConfig
    let onSave: (AreaConfig) -> Void

    var body: some View {
        Form {
            TextField("Name", text: $draft.name)
            Toggle("Enabled", isOn: $draft.enabled)
            HStack { Text("At + seconds"); TextField("", value: $draft.anchorSeconds, format: .number).frame(width: 90); Text("± seconds"); TextField("", value: $draft.jitterSeconds, format: .number).frame(width: 70) }
            Picker("Shape", selection: $draft.shape) { ForEach(AreaShape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            Picker("Order", selection: $draft.orderMode) { ForEach(AreaOrderMode.allCases, id: \.self) { Text($0.displayName).tag($0) } }
            TextField("Random group", text: $draft.randomGroup)
            if draft.orderMode == .randomTime {
                HStack { Text("Minimum spacing"); TextField("sec", value: $draft.minimumSpacingSeconds, format: .number).frame(width: 70) }
                Picker("Subset", selection: $draft.randomPickMode) { ForEach(RandomPickMode.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                if draft.randomPickMode != .all { HStack { Text("Min/Exact"); TextField("", value: $draft.randomPickMin, format: .number).frame(width: 65); Text("Max"); TextField("", value: $draft.randomPickMax, format: .number).frame(width: 65) } }
            }
            GroupBox("Click region (Quartz screen coordinates)") {
                Grid(alignment: .leading) {
                    GridRow { Text("X min"); TextField("", value: $draft.rect.xMin, format: .number).frame(width: 90); Text("X max"); TextField("", value: $draft.rect.xMax, format: .number).frame(width: 90) }
                    GridRow { Text("Y min"); TextField("", value: $draft.rect.yMin, format: .number).frame(width: 90); Text("Y max"); TextField("", value: $draft.rect.yMax, format: .number).frame(width: 90) }
                }
                HStack {
                    Button("Select Region…") { RegionPickerController.shared.pick(shape: draft.shape) { if let rect = $0 { draft.rect = rect } } }
                    Button("Use current cursor as center") {
                        if let p = CGEvent(source: nil)?.location { draft.rect = ClickRect(xMin: p.x-3, xMax: p.x+3, yMin: p.y-3, yMax: p.y+3) }
                    }
                }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { onSave(draft); dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 540)
    }
}

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedChromeID = ""

    var body: some View {
        TabView {
            Form {
                HStack { Text("Accessibility"); Spacer(); Text(app.accessibilityGranted ? "Granted" : "Required"); Button("Request") { app.refreshPermissions(prompt: true) }; Button("Open Settings") { MacPermission.openAccessibilitySettings() } }
                HStack { Text("Input Monitoring"); Spacer(); Text(app.inputMonitoringGranted ? "Granted" : "Required"); Button("Request") { app.refreshPermissions(prompt: true) }; Button("Open Settings") { MacPermission.openInputMonitoringSettings() } }
                Divider()
                HStack { Button("Refresh Chrome windows") { app.refreshChromeWindows() }; Text("Selected: \(app.chromeStatus())") }
                Picker("Chrome window", selection: $selectedChromeID) {
                    Text("Select…").tag("")
                    ForEach(app.chromeWindows) { Text($0.displayName).tag($0.id) }
                }.onChange(of: selectedChromeID) { id in if let w = app.chromeWindows.first(where: { $0.id == id }) { app.selectChromeWindow(w) } }
                Divider()
                HStack {
                    Text("Monitor layout")
                    Spacer()
                    Text(app.profile.savedMonitorSignature == app.monitorSignature() ? "Matches" : "Changed")
                    Button("Accept Current Layout") { app.acceptCurrentMonitorLayout() }
                }
            }.tabItem { Label("Browser & Permissions", systemImage: "globe") }

            Form {
                Picker("Profile", selection: Binding(get: { app.profile.randomness.profile }, set: { value in app.profile.randomness = RandomnessSettings.preset(value); app.saveProfile() })) {
                    ForEach(RandomnessProfile.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Stepper("Timing spread: \(app.profile.randomness.timingSpreadPercent)%", value: $app.profile.randomness.timingSpreadPercent, in: 1...100)
                Stepper("Extra pace: \(app.profile.randomness.paceVariationPercent)%", value: $app.profile.randomness.paceVariationPercent, in: 0...50)
                Stepper("Coordinate spread: \(app.profile.randomness.coordinateSpreadPercent)%", value: $app.profile.randomness.coordinateSpreadPercent, in: 1...100)
                Stepper("Random Time spread: \(app.profile.randomness.randomTimeSpreadPercent)%", value: $app.profile.randomness.randomTimeSpreadPercent, in: 1...100)
                HStack { Text("Click hold ms"); TextField("Min", value: $app.profile.randomness.clickHoldMinMs, format: .number).frame(width: 70); TextField("Max", value: $app.profile.randomness.clickHoldMaxMs, format: .number).frame(width: 70) }
                Button("Save Randomness") { app.saveProfile() }
            }.tabItem { Label("Randomness", systemImage: "dice") }

            Form {
                DelayRow("Activation", min: $app.profile.reliability.activationMinMs, max: $app.profile.reliability.activationMaxMs)
                DelayRow("Tab switch", min: $app.profile.reliability.tabSwitchMinMs, max: $app.profile.reliability.tabSwitchMaxMs)
                DelayRow("Before click", min: $app.profile.reliability.beforeClickMinMs, max: $app.profile.reliability.beforeClickMaxMs)
                DelayRow("After click", min: $app.profile.reliability.afterClickMinMs, max: $app.profile.reliability.afterClickMaxMs)
                DelayRow("Mouse settle", min: $app.profile.reliability.settleMinMs, max: $app.profile.reliability.settleMaxMs)
                DelayRow("Mouse movement", min: $app.profile.reliability.mouseMoveMinMs, max: $app.profile.reliability.mouseMoveMaxMs)
                HStack { Text("Mouse-busy timeout"); TextField("ms", value: $app.profile.reliability.inputBusyWaitMs, format: .number).frame(width: 90) }
                Button("Save Timing") { app.saveProfile() }
            }.tabItem { Label("Timing", systemImage: "timer") }
        }
        .padding(16).frame(width: 650, height: 480)
        .safeAreaInset(edge: .bottom) { HStack { Spacer(); Button("Close") { dismiss() } }.padding() }
    }
}

struct DelayRow: View {
    let title: String; @Binding var min: Int; @Binding var max: Int
    init(_ title: String, min: Binding<Int>, max: Binding<Int>) { self.title=title; _min=min; _max=max }
    var body: some View { HStack { Text(title).frame(width: 130, alignment: .leading); TextField("Min", value: $min, format: .number).frame(width: 80); Text("to"); TextField("Max", value: $max, format: .number).frame(width: 80); Text("ms") } }
}

struct AutoTimerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedStart: Bool
    @State private var offsetText = ""
    @State private var error = ""

    init(initialStartTab: Bool) { _selectedStart = State(initialValue: initialStartTab) }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Timer", selection: $selectedStart) { Text("Auto Start").tag(true); Text("Auto Stop").tag(false) }.pickerStyle(.segmented)
            HStack { Text("Clock offset"); TextField("UTC+1", text: $offsetText).frame(width: 120); Text("Current: \(app.currentClockText)") }
            if selectedStart { startForm } else { stopForm }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack { Button("Disarm") { selectedStart ? app.disarmAutoStart() : app.disarmAutoStop() }; Spacer(); Button("Close") { dismiss() }; Button(selectedStart ? "Save & Arm Start" : "Save & Arm Stop") { saveAndArm() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 560)
        .onAppear { offsetText = ClockTools.formatUTCOffset(app.profile.clockUTCOffsetMinutes) }
    }

    @ViewBuilder private var startForm: some View {
        Form {
            Picker("Mode", selection: $app.profile.autoStart.mode) { Text("After duration").tag(AutoTimerMode.duration); Text("At clock moment").tag(AutoTimerMode.clock) }
            if app.profile.autoStart.mode == .duration { DurationFields(seconds: $app.profile.autoStart.durationSeconds) }
            else { TextField("Date YYYY-MM-DD", text: $app.profile.autoStart.clockDate); TextField("Time HH:MM:SS", text: $app.profile.autoStart.clockTime) }
            Text(app.timerStatus(start: true)).font(.headline)
        }
    }

    @ViewBuilder private var stopForm: some View {
        Form {
            Picker("Mode", selection: $app.profile.autoStop.mode) { Text("After duration").tag(AutoTimerMode.duration); Text("At clock moment").tag(AutoTimerMode.clock) }
            Picker("When triggered", selection: $app.profile.autoStop.action) { Text("Stop All").tag(AutoStopAction.stop); Text("Exit app").tag(AutoStopAction.exit) }
            if app.profile.autoStop.mode == .duration { DurationFields(seconds: $app.profile.autoStop.durationSeconds) }
            else { TextField("Date YYYY-MM-DD", text: $app.profile.autoStop.clockDate); TextField("Time HH:MM:SS", text: $app.profile.autoStop.clockTime) }
            Text(app.timerStatus(start: false)).font(.headline)
        }
    }

    private func saveAndArm() {
        guard let offset = ClockTools.parseUTCOffset(offsetText) else { error = "Invalid UTC offset. Try UTC+1, UTC-5, +05:30, etc."; return }
        app.profile.clockUTCOffsetMinutes = offset; app.saveProfile(); error = (selectedStart ? app.armAutoStart() : app.armAutoStop()) ?? ""
    }
}

struct DurationFields: View {
    @Binding var seconds: Int
    var hours: Binding<Int> { Binding(get: { seconds/3600 }, set: { seconds = max(0,$0)*3600 + (seconds%3600) }) }
    var minutes: Binding<Int> { Binding(get: { (seconds%3600)/60 }, set: { seconds = (seconds/3600)*3600 + min(59,max(0,$0))*60 + seconds%60 }) }
    var secs: Binding<Int> { Binding(get: { seconds%60 }, set: { seconds = (seconds/60)*60 + min(59,max(0,$0)) }) }
    var body: some View { HStack { Text("Hours"); TextField("", value: hours, format: .number).frame(width:70); Text("Minutes"); TextField("", value: minutes, format: .number).frame(width:60); Text("Seconds"); TextField("", value: secs, format: .number).frame(width:60) } }
}

struct DiagnosticsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    var body: some View { VStack { ScrollView { Text(app.diagnostics()).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth:.infinity, alignment:.leading).padding() }; HStack { Button("Refresh permissions") { app.refreshPermissions(prompt:false) }; Spacer(); Button("Close") { dismiss() } }.padding() }.frame(width:700,height:500) }
}

struct PreviewView: View {
    @Environment(\.dismiss) var dismiss
    let text: String
    var body: some View { VStack { ScrollView { Text(text).font(.system(.body,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading).padding() }; Button("Close") { dismiss() }.padding() }.frame(width:520,height:560) }
}

struct RandomWindowView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var startID: UUID?
    @State private var stopID: UUID?
    @State private var spacing = 10
    @State private var mode: RandomPickMode = .all
    @State private var min = 4
    @State private var max = 8

    var body: some View {
        Form {
            Picker("Fixed Start area", selection: $startID) { Text("Select").tag(UUID?.none); ForEach(app.selectedRoutine?.areas ?? []) { Text($0.name).tag(Optional($0.id)) } }
            Picker("Fixed Stop area", selection: $stopID) { Text("Select").tag(UUID?.none); ForEach(app.selectedRoutine?.areas ?? []) { Text($0.name).tag(Optional($0.id)) } }
            Stepper("Minimum spacing: \(spacing)s", value: $spacing, in: 0...300)
            Picker("Middle-area subset", selection: $mode) { ForEach(RandomPickMode.allCases,id:\.self) { Text($0.displayName).tag($0) } }
            if mode != .all { Stepper("Min/Exact: \(min)", value: $min, in: 1...100); Stepper("Max: \(max)", value: $max, in: min...100) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Apply") { if let startID, let stopID { app.applyRandomWindow(startAreaID:startID, stopAreaID:stopID, spacingSeconds:spacing, pickMode:mode, min:min, max:max); dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width:480)
    }
}

struct ProfileManagerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var newName = "New Profile"
    @State private var message = ""
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Profiles").font(.title2.bold())
            List(app.profiles) { p in HStack { Text(p.name); Spacer(); if p.id==app.activeProfileID { Text("Active").foregroundStyle(.secondary) } } }
            HStack { TextField("New profile name",text:$newName); Button("New") { app.createProfile(name:newName) }; Button("Duplicate Active") { app.duplicateCurrentProfile() }; Button("Delete Active") { app.deleteCurrentProfile() }.disabled(app.profiles.count<=1) }
            HStack {
                Button("Restore Latest Backup") { message = app.restoreLatestBackup() ?? "Backup restored." }
                Button("Export Active…") { message = app.exportCurrentProfile() ?? "" }
                Button("Import…") { message = app.importProfileFromPanel() ?? "" }
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(message.contains("failed") ? .red : .secondary) }
            HStack { Spacer(); Button("Close") { dismiss() } }
        }.padding(20).frame(width:620,height:430)
    }
}

struct MiniView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) var openWindow
    var body: some View { VStack(spacing:8) { Text(app.runState.rawValue.uppercased()).font(.headline); Text(app.nextActionText).font(.title3).lineLimit(2); Text(app.currentClockText); HStack { Button("Start") { app.startAll() }; Button("Stop") { app.stopAll() }; Button("Full") { openWindow(id:"main"); NSApp.keyWindow?.orderOut(nil) } }; Text("\(app.timerStatus(start:true)) • \(app.timerStatus(start:false))").font(.caption) }.padding() }
}

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) var openWindow
    var body: some View { VStack(alignment:.leading) { Text("Bubbles — \(app.currentClockText)").font(.headline); Text(app.nextActionText).font(.caption); Divider(); Button("Open Bubbles") { openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) }; Button("Start All") { app.startAll() }; Button(app.runState == .paused ? "Resume" : "Pause") { app.runState == .paused ? app.resumeAll() : app.pauseAll() }; Button("Stop All") { app.stopAll() }; Divider(); Text(app.timerStatus(start:true)); Text(app.timerStatus(start:false)); Divider(); Button("Quit") { NSApp.terminate(nil) } }.padding(8).frame(width:280) }
}
#endif
