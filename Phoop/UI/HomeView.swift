import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var band: BandManager
    @EnvironmentObject private var sync: SyncEngine
    @EnvironmentObject private var store: DayStore
    @AppStorage(Settings.stepGoalKey) private var stepGoal = 11000

    private var d: DayMetrics { store.day }
    private var steps: Int { d.isToday ? max(d.steps, band.liveSport?.steps ?? 0) : d.steps }
    private var distance: Int { d.isToday ? max(d.distanceM, band.liveSport?.distanceM ?? 0) : d.distanceM }
    private var kcal: Int { d.isToday ? max(d.kcal, band.liveSport?.kcal ?? 0) : d.kcal }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header.appear(0)
                    rings.appear(0.05)
                    stepsBlock.appear(0.1)

                    Text(d.recommendation)
                        .font(Theme.body(14)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .appear(0.14)

                    metricsGrid.appear(0.18)

                    if d.isToday { sleepLine.appear(0.22) }

                    if !d.workouts.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(d.workouts) { w in
                                NavigationLink(value: Route.workout(w.id)) { WorkoutRow(w: w) }.pressable()
                            }
                        }
                    }

                    if sync.syncing {
                        Text(sync.status).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .refreshable { await sync.sync() }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                store.move(v.translation.width < 0 ? 1 : -1, context)
            })
            .routes()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Encabezado: día + batería

    private var header: some View {
        HStack(spacing: 4) {
            Button { store.move(-1, context) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 44)
            }
            Text(dayTitle)
                .font(Theme.display(28))
                .textCase(.uppercase)
                .contentTransition(.numericText())
            Button { store.move(1, context) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 44)
            }
            .opacity(d.isToday ? 0 : 1)
            .disabled(d.isToday)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(band.state == .ready ? Theme.recovery : Theme.secondary).frame(width: 6, height: 6)
                if let b = band.battery, band.state == .ready {
                    Text("\(b)%").font(Theme.body(13, .medium)).foregroundStyle(Theme.secondary)
                } else {
                    Text(band.state.label).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .foregroundStyle(Theme.text)
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
                Ring(progress: progress, color: color, lineWidth: 7, label: label, size: 96)
                Text(title).font(Theme.body(11, .medium)).textCase(.uppercase).tracking(0.8)
                    .foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .pressable()
    }

    // MARK: Pasos (justo debajo de los anillos)

    private var stepsBlock: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatSteps(steps))
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: Double(steps)))
                    .animation(.snappy, value: steps)
                Text("pasos").font(Theme.body(14)).foregroundStyle(Theme.secondary)
                Spacer()
                Text("meta \(formatSteps(stepGoal))").font(Theme.body(13)).foregroundStyle(Theme.secondary)
            }
            ProgressBar(value: Double(steps) / Double(max(1, stepGoal)), color: Theme.strain, height: 4)
            HStack(spacing: 16) {
                Text(String(format: "%.2f km", Double(distance) / 1000))
                Text("\(kcal) kcal")
                Spacer()
                if d.isToday, let hr = band.liveHR {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").foregroundStyle(Theme.bad)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("\(hr)").contentTransition(.numericText())
                    }
                }
            }
            .font(Theme.body(13)).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: Métricas (cuadrícula limpia)

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            tile(.hrv, "HRV", d.shownHRV.map(String.init), "ms")
            tile(.rhr, "Pulso reposo", d.restingHR.map(String.init), "lpm")
            tile(.spo2, "SpO₂", d.shownSpO2.map(String.init), "%")
            tile(nil, "Temperatura", d.shownTemp.map { String(format: "%.1f", $0) }, "°C")
        }
    }

    private func tile(_ metric: MetricsEngine.TrendMetric?, _ title: String, _ value: String?, _ unit: String) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.body(12)).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—").font(Theme.display(26, .semibold)).foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text(unit).font(Theme.body(12)).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        return Group {
            if let metric {
                NavigationLink(value: Route.metric(metric)) { content }.pressable()
            } else {
                content
            }
        }
    }

    // MARK: Entrenador de sueño (una línea)

    private var sleepLine: some View {
        let plan = MetricsEngine.sleepPlan(today: store.today)
        return NavigationLink(value: Route.sleep) {
            HStack(spacing: 10) {
                Image(systemName: "moon.fill").foregroundStyle(Theme.sleep)
                Text("Dormir a las \(plan.options[0].bedtime.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(Theme.text)
                Text("· despertar \(plan.wake.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .font(Theme.body(14))
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .pressable()
    }
}

struct WorkoutRow: View {
    let w: Workout
    var body: some View {
        let sport = SportType(rawValue: w.sport) ?? .other
        HStack(spacing: 12) {
            Image(systemName: sport.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.strain)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.sport).font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                Text("\(w.start.formatted(date: .omitted, time: .shortened)) · \(formatDuration(Int(w.end.timeIntervalSince(w.start)))) · \(w.kcal) kcal")
                    .font(Theme.body(12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(String(format: "%.1f", w.strain)).font(Theme.display(22, .semibold)).foregroundStyle(Theme.strain)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
