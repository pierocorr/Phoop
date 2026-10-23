import SwiftUI
import SwiftData

struct TrainView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var band: BandManager
    @StateObject private var wm = WorkoutManager.shared
    @Query(sort: \Workout.start, order: .reverse) private var workouts: [Workout]
    @State private var confirmEnd = false

    var body: some View {
        NavigationStack {
            Group {
                if wm.active { live } else { picker }
            }
            .routes()
            .toolbar(.hidden, for: .navigationBar)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: wm.active)
        }
    }

    // MARK: Elegir deporte

    private var picker: some View {
        Screen {
            ScreenTitle(title: "Entrenar").appear()
            Text("Elige una actividad. Peak mide tu pulso en vivo y calcula el esfuerzo, las zonas y las calorías.")
                .font(Theme.body(14)).foregroundStyle(Theme.secondary).appear(0.03)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(SportType.allCases.enumerated()), id: \.offset) { i, s in
                    Button { wm.begin(s) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: s.icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.strain)
                            Text(s.rawValue).font(Theme.display(18, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .pressable()
                    .disabled(band.state != .ready)
                    .opacity(band.state == .ready ? 1 : 0.5)
                    .appear(0.05 + Double(i) * 0.03)
                }
            }

            if band.state != .ready {
                Text("Conecta la pulsera para empezar.").font(Theme.body(13)).foregroundStyle(Theme.warn)
            }

            if !workouts.isEmpty {
                SectionLabel(text: "Historial").padding(.top, 6)
                ForEach(workouts.prefix(30)) { w in
                    NavigationLink(value: Route.workout(w.id)) { WorkoutRow(w: w) }.pressable()
                }
            }
        }
    }

    // MARK: En vivo

    private var live: some View {
        let zone = wm.currentZone
        let zoneColor = zone.map { Theme.zoneColors[$0] } ?? Theme.secondary
        return ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [zoneColor.opacity(0.25), .clear], center: .top, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1), value: zone)
            VStack(spacing: 22) {
                HStack {
                    Label(wm.sport.rawValue, systemImage: wm.sport.icon).font(Theme.display(22, .semibold)).textCase(.uppercase)
                    Spacer()
                    Text(formatClock(wm.elapsed)).font(Theme.display(26, .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Image(systemName: "heart.fill").font(.system(size: 30)).foregroundStyle(Theme.bad)
                        .symbolEffect(.pulse, options: .repeating, isActive: wm.hr != nil)
                    Text(wm.hr.map { "\($0)" } ?? "—").font(Theme.display(110)).foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text(zone.map { Theme.zoneNames[$0].uppercased() } ?? "BUSCANDO PULSO…")
                        .font(Theme.body(14, .bold)).tracking(1).foregroundStyle(zoneColor)
                }

                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i == zone ? Theme.zoneColors[i] : Theme.zoneColors[i].opacity(0.25))
                            .frame(height: i == zone ? 12 : 8)
                    }
                }
                .animation(.spring, value: zone)

                HStack(spacing: 10) {
                    Ring(progress: wm.strain / 21, color: Theme.strain, lineWidth: 8, label: String(format: "%.1f", wm.strain), sublabel: "esfuerzo", size: 104)
                    VStack(spacing: 8) {
                        StatTile(title: "Calorías", value: "\(Int(wm.kcal))", unit: "kcal")
                        StatTile(title: "Zona 4–5", value: formatDuration(wm.zoneSeconds[3] + wm.zoneSeconds[4]))
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(role: .destructive) { wm.cancel() } label: {
                        Text("Descartar").font(Theme.body(15, .semibold)).frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.card, in: Capsule())
                    }
                    Button { confirmEnd = true } label: {
                        Text("Terminar").font(Theme.body(16, .bold)).foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity, minHeight: 52).background(Theme.strain, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .confirmationDialog("¿Terminar el entrenamiento?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Guardar") { wm.finish(context: context) }
            Button("Seguir entrenando", role: .cancel) {}
        }
    }
}
