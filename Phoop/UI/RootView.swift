import SwiftUI
import SwiftData

/// Estado compartido de la interfaz: día seleccionado y sus métricas.
@MainActor
final class DayStore: ObservableObject {
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @Published private(set) var day = DayMetrics()
    @Published private(set) var today = DayMetrics()
    @Published private(set) var history: [DayMetrics] = []   // últimos 30 días
    @Published private(set) var insights: [MetricsEngine.Insight] = []

    func refresh(_ context: ModelContext) {
        today = MetricsEngine.compute(context: context)
        day = Calendar.current.isDateInToday(selectedDay) ? today : MetricsEngine.compute(context: context, day: selectedDay)
    }

    func refreshHistory(_ context: ModelContext) {
        history = MetricsEngine.history(context: context, days: 30)
        insights = MetricsEngine.journalInsights(context: context)
    }

    func move(_ delta: Int, _ context: ModelContext) {
        let cal = Calendar.current
        guard let d = cal.date(byAdding: .day, value: delta, to: selectedDay), d <= Date() else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDay = cal.startOfDay(for: d)
            refresh(context)
        }
    }

    func trend(_ m: MetricsEngine.TrendMetric, days: Int) -> [MetricsEngine.TrendPoint] {
        MetricsEngine.trend(m, from: Array(history.suffix(days)))
    }
}

enum Route: Hashable {
    case recovery, sleep, strain, journal, metric(MetricsEngine.TrendMetric), ecgHistory, workout(UUID)
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var band: BandManager
    @EnvironmentObject private var sync: SyncEngine
    @StateObject private var store = DayStore()
    @StateObject private var finder = PhoneFinder.shared
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
            HomeView().tag(0)
                .tabItem { Label("Inicio", systemImage: "circle.circle") }
            TrendsView().tag(1)
                .tabItem { Label("Tendencias", systemImage: "chart.bar.xaxis") }
            TrainView().tag(2)
                .tabItem { Label("Entrenar", systemImage: "figure.run") }
            HealthView().tag(3)
                .tabItem { Label("Salud", systemImage: "waveform.path.ecg") }
            MoreView().tag(4)
                .tabItem { Label("Más", systemImage: "line.3.horizontal") }
        }
        .tint(Theme.recovery)
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .task(id: sync.revision) {
            store.refresh(context)
            store.refreshHistory(context)
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                band.start()
                band.readPedometer()
                if band.state == .ready { band.send(YC.Cmd.realtime(true)) }
                store.refresh(context)
                Task { await sync.sync() }
            } else if p == .background, !WorkoutManager.shared.active {
                band.send(YC.Cmd.realtime(false))
            }
        }
        .overlay {
            if finder.ringing {
                FindPhoneOverlay { finder.stop() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: finder.ringing)
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
                .padding(.bottom, 28)
        }
        .background(Theme.bg.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }
}

/// Destinos de navegación compartidos.
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { r in
            switch r {
            case .recovery: RecoveryDetailView()
            case .sleep: SleepDetailView()
            case .strain: StrainDetailView()
            case .journal: JournalView()
            case .metric(let m): MetricDetailView(metric: m)
            case .ecgHistory: ECGHistoryView()
            case .workout(let id): WorkoutDetailView(id: id)
            }
        }
    }
}

extension View {
    func routes() -> some View { modifier(RouteDestinations()) }
}

struct FindPhoneOverlay: View {
    var stop: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 64)).foregroundStyle(Theme.recovery)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("Tu pulsera está buscando este teléfono").font(Theme.display(26)).multilineTextAlignment(.center)
                Button("Lo encontré", action: stop)
                    .font(Theme.body(16, .bold)).foregroundStyle(Theme.bg)
                    .frame(width: 220, height: 50).background(Theme.recovery, in: Capsule())
            }
            .padding(30)
        }
    }
}
