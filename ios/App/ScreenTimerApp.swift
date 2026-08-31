import SwiftUI

@main
struct ScreenTimerApp: App {
    @StateObject private var monitor = ScreenTimeMonitor()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(monitor)
                .task { await monitor.start() }
        }
    }
}
