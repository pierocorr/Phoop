import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var band: BandManager
    @EnvironmentObject private var sync: SyncEngine
    @EnvironmentObject private var store: DayStore
    @AppStorage(Settings.stepGoalKey) private var stepGoal = 11000
    @AppStorage(Settings.nameKey) private var name = ""
    @Query private var journal: [JournalEntry]

    private var d: DayMetrics { store.day }
    private var steps: Int { d.isToday ? max(d.steps, band.liveSport?.steps ?? 0) : d.steps }

    var body: some View {
        NavigationStack {
            Screen {
                header.appear(0)
                dayPager.appear(0.03)
                rings.appear(0.06)

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Recomendación").foregroundStyle(Theme.recoveryColor(d.recovery))
                        Text(d.recommendation).font(Theme.body(15)).foregroundStyle(Color(hex: 0xDDE2E8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .appear(0.1)

                if d.isToday {
                    sleepCoachCard.appear(0.13)
                    journalCard.appear(0.16)
                }

                SectionLabel(text: "Métricas clave").padding(.top, 4).appear(0.18)
                VStack(spacing: 8) {
                    NavigationLink(value: Route.metric(.hrv)) {
                        MetricRow(icon: "waveform.path.ecg", title: "HRV", subtitle: d.hrv != nil ? "Promedio nocturno" : "Última medición",
                                  value: d.shownHRV.map { "\($0) ms" } ?? "—", chevron: true)
                    }
                    NavigationLink(value: Route.metric(.rhr)) {
                        MetricRow(icon: "heart", title: "Pulso en reposo", subtitle: "Mínimo estable al dormir",
                                  value: d.restingHR.map { "\($0) lpm" } ?? "—", chevron: true)
                    }
                    NavigationLink(value: Route.metric(.spo2)) {
                        MetricRow(icon: "drop", title: "Oxígeno en sangre", subtitle: "SpO₂",
                                  value: d.shownSpO2.map { "\($0) %" } ?? "—", chevron: true)
                    }
                    NavigationLink(value: Route.metric(.stress)) {
                        MetricRow(icon: "brain.head.profile", title: "Estrés", subtitle: d.stress.map { DayMetrics.stressLabel($0) } ?? "Sin datos",
                                  value: d.stress.map { String(format: "%.0f", $0) } ?? "—", chevron: true)
                    }
                    MetricRow(icon: "lungs", title: "Respiración", subtitle: "Por minuto",
                              value: d.shownResp.map { "\($0) rpm" } ?? "—")
                    MetricRow(icon: "thermometer.medium", title: "Temperatura", subtitle: "Muñeca",
                              value: d.shownTemp.map { String(format: "%.1f °C", $0) } ?? "—")
                }
                .pressable()
                .appear(0.2)

                activityCard.appear(0.24)

                if !d.workouts.isEmpty {
                    SectionLabel(text: "Actividades").padding(.top, 4)
                    ForEach(d.workouts) { w in
                        NavigationLink(value: Route.workout(w.id)) { WorkoutRow(w: w) }.pressable()
                    }
                }

                if !sync.status.isEmpty {
                    Text(sync.syncing ? sync.status : "\(sync.status) · \(sync.lastSync?.formatted(date: .omitted, time: .shortened) ?? "")")
                        .font(Theme.body(12)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .refreshable { await sync.sync() }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                store.move(v.translation.width < 0 ? 1 : -1, context)
            })
            .routes()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Partes

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(Theme.body(13, .medium)).foregroundStyle(Theme.secondary).tracking(0.8)
                Text("Ritmo").font(Theme.display(34)).textCase(.uppercase).foregroundStyle(Theme.text)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(band.state == .ready ? Theme.recovery : Theme.secondary).frame(width: 8, height: 8)
                    .symbolEffect(.pulse, options: .repeating, isActive: sync.syncing)
                Text(band.state == .ready ? "\(BandManager.displayName) · \(band.battery.map { "\($0)%" } ?? "—")" : band.state.label)
                    .font(Theme.body(13)).foregroundStyle(Color(hex: 0xC9CFD6))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.card, in: Capsule())
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 12 ? "Buenos días" : (h < 19 ? "Buenas tardes" : "Buenas noches")
        return (name.isEmpty ? base : "\(base), \(name)").uppercased()
    }

    private var dayPager: some View {
        HStack {
            Button { store.move(-1, context) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 36)
            }
            Spacer()
            Text(dayTitle).font(Theme.display(20, .semibold)).textCase(.uppercase)
                .contentTransition(.numericText())
            Spacer()
            Button { store.move(1, context) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 36)
            }
            .disabled(d.isToday)
            .opacity(d.isToday ? 0.3 : 1)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.card, in: Capsule())
    }

    private var dayTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(d.day) { return "Hoy" }
        if cal.isDateInYesterday(d.day) { return "Ayer" }
        return d.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private var rings: some View {
        HStack(spacing: 8) {
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
            VStack(spacing: 8) {
                Ring(progress: progress, color: color, label: label)
                Text(title).font(Theme.body(11, .semibold)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .pressable()
    }

    private var sleepCoachCard: some View {
        let plan = MetricsEngine.sleepPlan(today: store.today)
        let best = plan.options[0]
        return NavigationLink(value: Route.sleep) {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 22)).foregroundStyle(Theme.sleep)
                        .frame(width: 44, height: 44).background(Theme.cardHi, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        SectionLabel(text: "Entrenador de sueño")
                        Text("Acuéstate a las \(best.bedtime.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.display(22, .semibold)).foregroundStyle(Theme.text)
                        Text("para despertar a las \(plan.wake.formatted(date: .omitted, time: .shortened)) al 100 %")
                            .font(Theme.body(13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .pressable()
    }

    private var journalCard: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let done = journal.contains { $0.day == today && !$0.answered.isEmpty }
        return NavigationLink(value: Route.journal) {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: done ? "checkmark.circle.fill" : "book.closed.fill").font(.system(size: 22))
                        .foregroundStyle(done ? Theme.recovery : Theme.warn)
                        .frame(width: 44, height: 44).background(Theme.cardHi, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        SectionLabel(text: "Diario")
                        Text(done ? "Diario de hoy completo" : "¿Cómo fue tu día?").font(Theme.display(22, .semibold)).foregroundStyle(Theme.text)
                        Text("Descubre qué hábitos mejoran tu recuperación").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .pressable()
    }

    private var activityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Actividad")
                    Spacer()
                    if d.isToday { LiveHeart(bpm: band.liveHR) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatSteps(steps)).font(Theme.display(34)).foregroundStyle(Theme.text).contentTransition(.numericText())
                    Text("de \(formatSteps(stepGoal)) pasos").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                }
                ProgressBar(value: Double(steps) / Double(max(1, stepGoal)), color: Theme.strain, height: 8)
                HStack {
                    Label(String(format: "%.2f km", Double(d.isToday ? max(d.distanceM, band.liveSport?.distanceM ?? 0) : d.distanceM) / 1000),
                          systemImage: "location")
                    Spacer()
                    Label("\(d.isToday ? max(d.kcal, band.liveSport?.kcal ?? 0) : d.kcal) kcal", systemImage: "flame")
                }
                .font(Theme.body(13)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

struct WorkoutRow: View {
    let w: Workout
    var body: some View {
        let sport = SportType(rawValue: w.sport) ?? .other
        Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: sport.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.strain)
                    .frame(width: 40, height: 40).background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.sport).font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                    Text("\(w.start.formatted(date: .omitted, time: .shortened)) · \(formatDuration(Int(w.end.timeIntervalSince(w.start)))) · \(w.kcal) kcal")
                        .font(Theme.body(12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(String(format: "%.1f", w.strain)).font(Theme.display(24, .semibold)).foregroundStyle(Theme.strain)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
        }
    }
}
