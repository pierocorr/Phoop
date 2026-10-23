import SwiftUI
import SwiftData

@main
struct PhoopApp: App {
    let container: ModelContainer

    init() {
        Settings.registerDefaults()
        container = try! ModelContainer(for: Schema(PhoopSchema.models))
        SyncEngine.registerBackground()
        SyncEngine.shared.attach(container)
        BandManager.shared.start()
        SyncEngine.scheduleBackground()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(BandManager.shared)
                .environmentObject(SyncEngine.shared)
                .task {
                    if Settings.healthSync { _ = await HealthSync.shared.requestAuthorization() }
                }
        }
        .modelContainer(container)
    }
}
