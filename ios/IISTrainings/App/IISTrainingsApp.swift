import SwiftUI

@main
struct IISTrainingsApp: App {
    @State private var store = TrainingStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Chalk.yellow)
                .task { await store.refreshIfStale(maxAge: 0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await store.refreshIfStale() }
                    }
                }
        }
    }
}
