#if os(macOS)
import SwiftUI
import BubblesCore

@main
struct BubblesAutoclickerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Bubbles Autoclicker", id: "main") {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 650)
        }
        .defaultSize(width: 1050, height: 780)

        Window("Bubbles Mini", id: "mini") {
            MiniView()
                .environmentObject(appState)
                .frame(width: 340, height: 170)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Bubbles", systemImage: "cursorarrow.click.2") {
            MenuBarView()
                .environmentObject(appState)
        }
    }
}
#else
import Foundation
@main
struct BubblesAutoclickerUnsupported {
    static func main() {
        print("Bubbles Autoclicker app target is macOS-only. The shared core builds on this platform for tests.")
    }
}
#endif
