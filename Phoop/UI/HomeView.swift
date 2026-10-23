import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var band: BandManager
    @EnvironmentObject private var sync: SyncEngine
    @EnvironmentObject private var store: DayStore
    @StateObject private var wm = WorkoutManager.shared
    @AppStorage(Settings.stepGoalKey) private var stepGoal = 11000
    @AppStorage(Settings.nameKey) private var name = ""

    private var d: DayMetrics { store.day }
    private var steps: Int { d.isToday ? max(d.steps, band.liveSport?.steps ?? 0) : d.steps }
    private var distance: Int { d.isToday ? max(d.distanceM, band.liveSport?.distanceM ?? 0) : d.distanceM }
    private var kcal: Int { d.isToday ? max(d.kcal, band.liveSport?.kcal ?? 0) : d.kcal }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 22) {
                        topBar.appear(0)
                        HStack(spacing: 8) {
                            Image(systemName: "mountain.2").font(.system(size: 14, weight: .semibold))
                            Text(AppInfo.name.uppercased()).font(Theme.body(15, .semibold)).tracking(4)
                        }
                        .foregroundStyle(Theme.text.opacity(0.85))
                            .appear(0.02)
                        rings.appear(0.05)
                        stepsCard.appear(0.09)
                        monitors.appear(0.13)
                        if wm.active { liveWorkoutBanner.appear(0) }
                        myDay.appear(0.17)
                        if sync.syncing {
                            Text(sync.status).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
                .refreshable { await sync.sync() }
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    store.move(v.translation.width < 0 ? 1 : -1, context)
                })

                // Botón flotante: iniciar actividad
                Button { store.showTrain = true } label: {
                    Image(systemName: "plus").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.bg)
                        .frame(width: 58, height: 58).background(Theme.text, in: Circle())
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                }
                .accessibilityLabel("Iniciar actividad")
                .pressable()
                .padding(.trailing, 20).padding(.bottom, 18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .routes()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Barra superior: avatar · día · batería

    private var topBar: some View {
        HStack {
            Button { store.tab = 3 } label: {
                Text(name.first.map { String($0).uppercased() } ?? "")
                    .font(Theme.body(15, .bold)).foregroundStyle(Theme.bg)
                    .frame(width: 36, height: 36)
                    .background(Theme.recovery, in: Circle())
                    .overlay {
                        if name.isEmpty { Image(systemName: "person.fill").foregroundStyle(Theme.bg) }
                    }
            }
            .accessibilityLabel("Perfil")
            Spacer()
            HStack(spacing: 0) {
                Button { store.move(-1, context) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).frame(width: 36, height: 34)
                }
                Text(dayTitle)
                    .font(Theme.body(12, .bold)).tracking(1.2).textCase(.uppercase)
                    .padding(.horizontal, 14).frame(height: 28)
                    .background(Theme.cardHi, in: Capsule())
                    .contentTransition(.numericText())
                Button { store.move(1, context) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).frame(width: 36, height: 34)
                }
                .opacity(d.isToday ? 0.3 : 1)
                .disabled(d.isToday)
            }
            .foregroundStyle(Theme.text)
            .background(Theme.card, in: Capsule())
            Spacer()
            HStack(spacing: 6) {
                Text(band.battery.map { "\($0)%" } ?? "—").font(Theme.body(12, .medium)).foregroundStyle(Theme.secondary)
                Image(systemName: "applewatch.side.right").font(.system(size: 18))
                    .foregroundStyle(Theme.text)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(band.state == .ready ? Theme.recovery : Theme.bad).frame(width: 7, height: 7).offset(x: 3, y: -2)
                    }
            }
            .frame(width: 70, alignment: .trailing)
        }
    }

    private var dayTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(d.day) { return "Hoy" }
        if cal.isDateInYesterday(d.day) { return "Ayer" }
        return d.day.formatted(.dateTime.weekday(.abbreviated).day())
    }

    // MARK: Anillos

    private var rings: some View {
        HStack(spacing: 0) {
            ringLink(.sleep, progress: d.sleepPerformance ?? 0, color: Theme.sleep,
                     label: d.sleepPerformance.map { "\(Int($0 * 100))%" } ?? "—", title: "Sueño")
            ringLink(.recovery, progress: Double(d.recovery ?? 0) / 100, color: Theme.recoveryColor(d.recovery),
                     label: d.recovery.map { "\($0)%" } ?? "—", title: "Recuperación")
            ringLink(.strain, progress: d.strain / 21, color: Theme.strain,
                     label: String(format: "%.1f", d.strain), title: "Esfuerzo")
        }
        .id(d.day)
    }

    private func ringLink(_ r: Route, progress: Double, color: Color, label: String, title: String) -> some View {
        NavigationLink(value: r) {
            VStack(spacing: 10) {
                Ring(progress: progress, color: color, lineWidth: 8, label: label, size: 100)
                HStack(spacing: 3) {
                    Text(title).font(Theme.body(11, .bold)).textCase(.uppercase).tracking(0.8)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.text.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
        }
        .pressable()
    }

    // MARK: Pasos

    private var stepsCard: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatSteps(steps))
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: Double(steps)))
                    .animation(.snappy, value: steps)
                Text("pasos").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                Spacer()
                if d.isToday, let hr = band.liveHR {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").foregroundStyle(Theme.bad)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("\(hr)").font(Theme.body(14, .semibold)).contentTransition(.numericText())
                    }
                }
            }
            ProgressBar(value: Double(steps) / Double(max(1, stepGoal)), color: Theme.strain, height: 4)
            HStack(spacing: 14) {
                Text(String(format: "%.2f km", Double(distance) / 1000))
                Text("\(kcal) kcal")
                Spacer()
                Text("meta \(formatSteps(stepGoal))")
            }
            .font(Theme.body(12)).foregroundStyle(Theme.secondary)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Monitores de salud y estrés

    private var monitors: some View {
        HStack(spacing: 10) {
            Button { store.tab = 1 } label: {
                monitorCard(title: "Monitor de salud") {
                    HStack(spacing: 8) {
                        Image(systemName: health.icon).foregroundStyle(health.color)
                            .frame(width: 26, height: 26).background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 7))
                        Text(health.text).font(Theme.body(13)).foregroundStyle(Theme.text).lineLimit(2)
                    }
                }
            }
            .pressable()
            NavigationLink(value: Route.metric(.stress)) {
                monitorCard(title: "Monitor de estrés") {
                    HStack(spacing: 8) {
                        Text(d.stress.map { String(format: "%.0f", $0) } ?? "—")
                            .font(Theme.body(13, .bold)).foregroundStyle(Theme.stressColor(d.stress))
                            .frame(width: 30, height: 26).background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.stress.map { DayMetrics.stressLabel($0).uppercased() } ?? "SIN DATOS")
                                .font(Theme.body(12, .bold)).foregroundStyle(Theme.stressColor(d.stress))
                            if let t = d.stressSeries.last?.0 {
                                Text(t.formatted(date: .omitted, time: .shortened)).font(Theme.body(11)).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
            }
            .pressable()
        }
    }

    private func monitorCard<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(Theme.body(11, .bold)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.secondary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Estado general: compara tus signos con lo normal y con tu promedio.
    private var health: (icon: String, color: Color, text: String) {
        guard d.hrvBaseline != nil || d.shownSpO2 != nil || d.shownTemp != nil else {
            return ("circle.dotted", Theme.secondary, "Calibrando")
        }
        var out = 0
        if let s = d.shownSpO2, s < 95 { out += 1 }
        if let t = d.shownTemp, t < 35.5 || t > 37.5 { out += 1 }
        if let r = d.restingHR, let b = d.restingHRBaseline, r > b + 5 { out += 1 }
        if let h = d.hrv, let b = d.hrvBaseline, Double(h) < Double(b) * 0.75 { out += 1 }
        return out == 0
            ? ("checkmark", Theme.recovery, "Dentro de lo normal")
            : ("exclamationmark", Theme.warn, "\(out) fuera de rango")
    }

    // MARK: Mi día

    private var liveWorkoutBanner: some View {
        Button { store.showTrain = true } label: {
            HStack(spacing: 10) {
                Image(systemName: wm.sport.icon).foregroundStyle(Theme.strain)
                Text("\(wm.sport.rawValue) en curso").font(Theme.body(14, .semibold))
                Spacer()
                Text(formatClock(wm.elapsed)).font(Theme.body(14, .semibold)).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.secondary)
            }
            .foregroundStyle(Theme.text)
            .padding(14)
            .background(Theme.strain.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .pressable()
    }

    private var myDay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mi día").font(Theme.body(22, .bold)).foregroundStyle(Theme.text)

            if d.isToday {
                let plan = MetricsEngine.sleepPlan(today: store.today)
                NavigationLink(value: Route.sleep) {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.fill").foregroundStyle(Theme.sleep)
                            .frame(width: 26, height: 26).background(Theme.cardHi, in: Circle())
                        Text("Dormir a las \(plan.options[0].bedtime.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.body(14)).foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.secondary)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .pressable()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(d.isToday ? "Actividades de hoy" : "Actividades")
                    .font(Theme.body(11, .bold)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.text)
                    .padding(14)
                if d.workouts.isEmpty {
                    Text("Sin actividades. Toca + para iniciar una.")
                        .font(Theme.body(13)).foregroundStyle(Theme.secondary)
                        .padding([.horizontal, .bottom], 14)
                } else {
                    ForEach(d.workouts) { w in
                        Divider().overlay(Theme.divider)
                        NavigationLink(value: Route.workout(w.id)) { WorkoutRow(w: w, plain: true) }.pressable()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct WorkoutRow: View {
    let w: Workout
    var plain = false
    var body: some View {
        let sport = SportType(rawValue: w.sport) ?? .other
        HStack(spacing: 12) {
            Text(String(format: "%.1f", w.strain)).font(Theme.body(14, .bold)).foregroundStyle(Theme.bg)
                .frame(width: 44, height: 30).background(Theme.strain, in: RoundedRectangle(cornerRadius: 8))
            Image(systemName: sport.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.sport.uppercased()).font(Theme.body(13, .bold)).foregroundStyle(Theme.text)
                Text("\(w.start.formatted(date: .omitted, time: .shortened)) – \(w.end.formatted(date: .omitted, time: .shortened)) · \(w.kcal) kcal")
                    .font(Theme.body(12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.secondary)
        }
        .padding(14)
        .background(plain ? Color.clear : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Nombre visible de la app (un solo lugar para cambiarlo).
enum AppInfo {
    static let name = "Peak"
}
