import SwiftUI

@main
struct RepTrackApp: App {
    @State private var store = DataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                // Re-check the data file whenever the user switches back to this app.
                // This is the safety net for cases where the file watcher missed a cloud-sync write.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)
                ) { _ in
                    store.reloadIfNeeded()
                }
        }
        .defaultSize(width: 720, height: 740)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
