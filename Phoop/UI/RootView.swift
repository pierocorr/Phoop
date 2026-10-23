import SwiftUI
import SwiftData

@MainActor
final class MetricsStore: ObservableObject {
    @Published var day = DayMetrics()
    @Published var week: [(Date, Int?)] = []

    func refresh(_ context: ModelContext) {
        day = MetricsEngine.compute(context: context)
        week = MetricsEngine.recoveryHistory(context: context)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var band: BandManager
    @EnvironmentObject private var sync: SyncEngine
    @StateObject private var metrics = MetricsStore()
    @State private var tab = 0

    init() {
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = UIColor(Theme.tabBar)
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }

    var body: some View {
        TabView(selection: $tab) {
            TodayView(tab: $tab).tag(0)
                .tabItem { Label("Hoy", systemImage: "house") }
            SleepView().tag(1)
                .tabItem { Label("Sueño", systemImage: "moon") }
            RecoveryView().tag(2)
                .tabItem { Label("Recuperar", systemImage: "heart") }
            StrainView().tag(3)
                .tabItem { Label("Esfuerzo", systemImage: "bolt") }
            BandView().tag(4)
                .tabItem { Label("Pulsera", systemImage: "applewatch") }
        }
        .tint(tabTint)
        .environmentObject(metrics)
        .preferredColorScheme(.dark)
        .task(id: sync.revision) { metrics.refresh(context) }
        .onChange(of: phase) { _, p in
            if p == .active {
                band.start()
                band.readPedometer()
                metrics.refresh(context)
                Task { await sync.sync() }
            }
        }
    }

    private var tabTint: Color {
        switch tab {
        case 1: return Theme.sleep
        case 3: return Theme.strain
        default: return Theme.recovery
        }
    }
}

/// Contenedor común de pantalla: fondo oscuro + scroll.
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }
}
