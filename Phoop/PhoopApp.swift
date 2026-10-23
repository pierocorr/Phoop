import SwiftUI
import SwiftData

@main
struct PeakApp: App {
    let container: ModelContainer

    init() {
        Settings.registerDefaults()
        container = try! ModelContainer(for: Schema(PhoopSchema.models))
        SyncEngine.registerBackground()
        SyncEngine.shared.attach(container)
        BandManager.shared.start()
        _ = PhoneFinder.shared
        _ = MeasureManager.shared
        _ = ECGManager.shared
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
