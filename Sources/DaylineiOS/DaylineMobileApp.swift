import SwiftUI

@main
struct DaylineMobileApp: App {
    @StateObject private var store = TaskStore(syncService: CloudKitTaskSyncService())

    var body: some Scene {
        WindowGroup {
            DaylineMobileView()
                .environmentObject(store)
        }
    }
}
