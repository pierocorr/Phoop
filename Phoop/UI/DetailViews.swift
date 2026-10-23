import SwiftUI
import SwiftData
import Charts

// MARK: - Recuperación

struct RecoveryDetailView: View {
    @EnvironmentObject private var store: DayStore
    private var d: DayMetrics { store.day }

    var body: some View {
        Screen {
            VStack(spacing: 10) {
                Ring(progress: Double(d.recovery ?? 0) / 100, color: Theme.recoveryColor(d.recovery), lineWidth: 14,
                     label: d.recovery.map { "\($0)%" } ?? "—", sublabel: bandLabel, size: 210)
                Text(d.recovery == nil
                     ? "Aún no hay datos de sueño para este día. Duerme con la pulsera puesta y sincroniza al despertar."
                     : "Calculada con tu HRV, pulso en reposo y sueño, comparados con tus últimas 2 semanas.")
                    .font(Theme.body(14)).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8).appear()

            Card {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Qué significa")
                    Text(d.recommendation).font(Theme.body(15)).foregroundStyle(Theme.text)
                }
            }.appear(0.05)

            VStack(spacing: 8) {
                NavigationLink(value: Route.metric(.hrv)) {
                    MetricRow(icon: "waveform.path.ecg", title: "HRV", subtitle: "Variabilidad cardíaca",
                              value: d.shownHRV.map { "\($0) ms" } ?? "—",
                              delta: delta(d.hrv, d.hrvBaseline), deltaGood: (d.hrv ?? 0) >= (d.hrvBaseline ?? 0), chevron: true)
                }
                NavigationLink(value: Route.metric(.rhr)) {
                    MetricRow(icon: "heart", title: "Pulso en reposo", subtitle: "Mínimo estable al dormir",
                              value: d.restingHR.map { "\($0) lpm" } ?? "—",
                              delta: delta(d.restingHR, d.restingHRBaseline), deltaGood: (d.restingHR ?? 0) <= (d.restingHRBaseline ?? 999), chevron: true)
                }
                NavigationLink(value: Route.sleep) {
                    MetricRow(icon: "moon", title: "Rendimiento de sueño", subtitle: "Horas dormidas vs. necesarias",
                              value: d.sleepPerformance.map { "\(Int($0 * 100)) %" } ?? "—", chevron: true)
                }
                MetricRow(icon: "drop", title: "Oxígeno (SpO₂)", subtitle: "Noche", value: d.shownSpO2.map { "\($0) %" } ?? "—")
                MetricRow(icon: "lungs", title: "Respiración", subtitle: "Noche", value: d.shownResp.map { "\($0) rpm" } ?? "—")
                MetricRow(icon: "thermometer.medium", title: "Temperatura", subtitle: "Muñeca",
                          value: d.shownTemp.map { String(format: "%.1f °C", $0) } ?? "—")
            }
            .pressable().appear(0.1)

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Últimos 30 días")
                    TrendChart(points: store.trend(.recovery, days: 30), color: Theme.recovery)
                }
            }.appear(0.15)
        }
        .navigationTitle("Recuperación")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bandLabel: String? {
        switch d.recoveryBand {
        case .high: return "Alta"
        case .medium: return "Moderada"
        case .low: return "Baja"
        case .none: return nil
        }
    }

    private func delta(_ v: Int?, _ base: Int?) -> String? {
        guard let v, let base, v != base else { return nil }
        let diff = v - base
        return "\(diff > 0 ? "▲" : "▼") \(abs(diff)) vs. promedio"
    }
}

// MARK: - Sueño

struct SleepDetailView: View {
    @EnvironmentObject private var store: DayStore
    @AppStorage(Settings.wakeMinutesKey) private var wakeMinutes = 420
    @AppStorage(Settings.sleepNeedKey) private var sleepNeed = 8.0
    private var d: DayMetrics { store.day }

    var body: some View {
        Screen {
            if let s = d.sleep {
                Card(padding: 18) {
                    HStack(spacing: 18) {
                        Ring(progress: d.sleepPerformance ?? 0, color: Theme.sleep,
                             label: "\(Int((d.sleepPerformance ?? 0) * 100))%", sublabel: "rendimiento", size: 112)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDuration(s.asleepSeconds)).font(Theme.display(30)).foregroundStyle(Theme.text)
                            Text("\(s.start.formatted(date: .omitted, time: .shortened)) – \(s.end.formatted(date: .omitted, time: .shortened))")
                                .font(Theme.body(13)).foregroundStyle(Theme.secondary)
                            if d.sleepDebtSeconds > 0 {
                                Text("Deuda: \(formatDuration(d.sleepDebtSeconds))").font(Theme.body(13)).foregroundStyle(Theme.rem)
                            }
                        }
                    }
                }.appear()

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Fases")
                        Hypnogram(session: s)
                    }
                }.appear(0.05)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    stageTile("Profundo", s.seconds(.deep), s, Theme.deep)
                    stageTile("REM", s.seconds(.rem), s, Theme.rem)
                    stageTile("Ligero", s.seconds(.light), s, Theme.light)
                    StatTile(title: "Despierto · \(s.wakeCount) veces", value: formatDuration(s.seconds(.awake)))
                }.appear(0.1)
            } else {
                Card {
                    Text("No hay una noche registrada para este día. Duerme con la pulsera puesta y abre Peak al despertar.")
                        .font(Theme.body(15)).foregroundStyle(Theme.secondary)
                }.appear()
            }

            coach.appear(0.15)

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Horas dormidas · 30 días")
                    TrendChart(points: store.trend(.sleep, days: 30), color: Theme.sleep)
                }
            }.appear(0.2)
        }
        .navigationTitle("Sueño")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stageTile(_ title: String, _ secs: Int, _ s: SleepSession, _ color: Color) -> some View {
        let pct = s.asleepSeconds > 0 ? Int(Double(secs) / Double(s.asleepSeconds) * 100) : 0
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(title).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text("\(pct) %").font(Theme.body(12, .semibold)).foregroundStyle(color)
                }
                Text(formatDuration(secs)).font(Theme.display(22, .semibold)).foregroundStyle(Theme.text)
            }
        }
    }

    private var coach: some View {
        let plan = MetricsEngine.sleepPlan(today: store.today)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Entrenador de sueño · esta noche")
                ForEach(plan.options, id: \.label) { o in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.label).font(Theme.body(14, .semibold)).foregroundStyle(Theme.text)
                            Text(String(format: "%.1f h de sueño", o.hours)).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Text(o.bedtime.formatted(date: .omitted, time: .shortened)).font(Theme.display(24, .semibold)).foregroundStyle(Theme.sleep)
                    }
                }
                Divider().overlay(Theme.divider)
                DatePicker("Quiero despertar a las", selection: wakeBinding, displayedComponents: .hourAndMinute)
                    .font(Theme.body(14)).tint(Theme.sleep)
                Stepper(value: $sleepNeed, in: 5...11, step: 0.5) {
                    HStack {
                        Text("Sueño que necesitas").font(Theme.body(14))
                        Spacer()
                        Text(String(format: "%.1f h", sleepNeed)).font(Theme.body(14)).foregroundStyle(Theme.secondary)
                    }
                }
                Text("Se ajusta según tu deuda de sueño y el esfuerzo del día.").font(Theme.body(12)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var wakeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: wakeMinutes / 60, minute: wakeMinutes % 60, second: 0, of: Date()) ?? Date() },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); wakeMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0) }
        )
    }
}

/// Gráfico de fases tipo escalera: cada fase en su altura.
struct Hypnogram: View {
    let session: SleepSession
    private let rows: [(SleepStageType, Color)] = [(.awake, Theme.awake), (.rem, Theme.rem), (.light, Theme.light), (.deep, Theme.deep)]

    var body: some View {
        let total = max(1, session.end.timeIntervalSince(session.start))
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { stage, color in
                HStack(spacing: 8) {
                    Text(stage.label).font(Theme.body(11)).foregroundStyle(Theme.secondary).frame(width: 62, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.cardHi)
                            ForEach(session.stages.filter { $0.type == stage.rawValue }, id: \.self) { st in
                                let x = st.start.timeIntervalSince(session.start) / total
                                let w = Double(st.seconds) / total
                                RoundedRectangle(cornerRadius: 4).fill(color)
                                    .frame(width: max(2, g.size.width * w))
                                    .offset(x: g.size.width * max(0, x))
                            }
                        }
                    }
                    .frame(height: 16)
                }
            }
            HStack {
                Text(session.start.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(session.end.formatted(date: .omitted, time: .shortened))
            }
            .font(Theme.body(11)).foregroundStyle(Theme.secondary).padding(.leading, 70)
        }
    }
}

// MARK: - Esfuerzo

struct StrainDetailView: View {
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var band: BandManager
    private var d: DayMetrics { store.day }

    var body: some View {
        Screen {
            Card(padding: 18) {
                HStack(spacing: 18) {
                    Ring(progress: d.strain / 21, color: Theme.strain, label: String(format: "%.1f", d.strain), sublabel: "de 21", size: 112)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DayMetrics.strainLabel(d.strain)).font(Theme.display(26)).textCase(.uppercase).foregroundStyle(Theme.text)
                        Text("Objetivo según tu recuperación: \(Int(d.strainTarget.lowerBound))–\(Int(d.strainTarget.upperBound))")
                            .font(Theme.body(13)).foregroundStyle(Theme.warn)
                        ProgressBar(value: d.strain / max(1, d.strainTarget.upperBound), color: Theme.strain).padding(.top, 4)
                    }
                }
            }.appear()

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel(text: "Pulso del día")
                        Spacer()
                        if d.isToday { LiveHeart(bpm: band.liveHR) }
                    }
                    if d.hrToday.count > 1 {
                        Chart(Array(d.hrToday.enumerated()), id: \.offset) { _, p in
                            AreaMark(x: .value("Hora", p.0), y: .value("lpm", p.1))
                                .foregroundStyle(LinearGradient(colors: [Theme.strain.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Hora", p.0), y: .value("lpm", p.1))
                                .foregroundStyle(Theme.strain)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Theme.secondary) } }
                        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Theme.divider); AxisValueLabel().foregroundStyle(Theme.secondary) } }
                        .frame(height: 140)
                    } else {
                        Text("El gráfico aparecerá cuando haya más mediciones.").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                    }
                }
            }.appear(0.05)

            ZonesCard(minutes: d.zoneMinutes).appear(0.1)

            if !d.workouts.isEmpty {
                SectionLabel(text: "Actividades")
                ForEach(d.workouts) { w in
                    NavigationLink(value: Route.workout(w.id)) { WorkoutRow(w: w) }.pressable()
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Esfuerzo · 30 días")
                    TrendChart(points: store.trend(.strain, days: 30), color: Theme.strain)
                }
            }.appear(0.15)
        }
        .navigationTitle("Esfuerzo")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ZonesCard: View {
    var minutes: [Int]
    var title = "Tiempo en zonas cardíacas"
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: title)
                let maxMin = max(1, minutes.max() ?? 1)
                ForEach((0..<5).reversed(), id: \.self) { i in
                    HStack(spacing: 10) {
                        Text(Theme.zoneNames[i]).font(Theme.body(12)).foregroundStyle(Color(hex: 0xC9CFD6)).frame(width: 74, alignment: .leading)
                        ProgressBar(value: Double(minutes[i]) / Double(maxMin), color: Theme.zoneColors[i], height: 10)
                        Text(formatDuration(minutes[i] * 60)).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Detalle de una métrica

struct MetricDetailView: View {
    let metric: MetricsEngine.TrendMetric
    @EnvironmentObject private var store: DayStore
    @State private var range = 7

    private var color: Color {
        switch metric {
        case .recovery: return Theme.recovery
        case .strain, .steps: return Theme.strain
        case .sleep: return Theme.sleep
        case .hrv, .spo2: return Theme.health
        case .rhr: return Theme.bad
        case .stress: return Theme.warn
        }
    }

    var body: some View {
        let points = store.trend(metric, days: range)
        let values = points.map(\.value)
        Screen {
            Picker("Rango", selection: $range) {
                Text("7 días").tag(7)
                Text("30 días").tag(30)
            }
            .pickerStyle(.segmented)

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(values.last.map(format) ?? "—").font(Theme.display(40)).foregroundStyle(Theme.text)
                            .contentTransition(.numericText())
                        Text(metric.unit).font(Theme.body(14)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("último").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                    }
                    TrendChart(points: points, color: color, height: 180)
                }
            }
            .animation(.easeInOut, value: range)

            HStack(spacing: 8) {
                StatTile(title: "Promedio", value: values.isEmpty ? "—" : format(values.reduce(0, +) / Double(values.count)), unit: metric.unit)
                StatTile(title: "Mínimo", value: values.min().map(format) ?? "—", unit: metric.unit)
                StatTile(title: "Máximo", value: values.max().map(format) ?? "—", unit: metric.unit)
            }

            Card {
                Text(explanation).font(Theme.body(14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func format(_ v: Double) -> String {
        switch metric {
        case .strain, .sleep: return String(format: "%.1f", v)
        case .steps: return formatSteps(Int(v))
        default: return String(format: "%.0f", v)
        }
    }

    private var explanation: String {
        switch metric {
        case .hrv: return "La variabilidad de la frecuencia cardíaca refleja cuánto se está recuperando tu sistema nervioso. Más alta que tu promedio suele indicar buena recuperación."
        case .rhr: return "El pulso en reposo se mide mientras duermes. Si sube varios latidos sobre tu promedio puede ser señal de cansancio, estrés o una enfermedad que empieza."
        case .spo2: return "Saturación de oxígeno en sangre. En reposo lo normal es 95–100 %. Es una estimación de la pulsera, no un dato médico."
        case .stress: return "Índice de estrés de 0 a 100 calculado por la pulsera a partir de tu variabilidad cardíaca."
        case .recovery: return "Qué tan preparado está tu cuerpo para exigirse hoy, de 0 a 100 %."
        case .strain: return "Carga cardiovascular del día en escala 0–21, calculada con el tiempo que pasaste en cada zona de pulso."
        case .sleep: return "Horas dormidas cada noche, sin contar los despertares."
        case .steps: return "Pasos contados por la pulsera cada día."
        }
    }
}

// MARK: - Detalle de un entrenamiento

struct WorkoutDetailView: View {
    let id: UUID
    @Query private var workouts: [Workout]

    init(id: UUID) {
        self.id = id
        _workouts = Query(filter: #Predicate<Workout> { $0.id == id })
    }

    var body: some View {
        Screen {
            if let w = workouts.first {
                Card(padding: 18) {
                    HStack(spacing: 18) {
                        Ring(progress: w.strain / 21, color: Theme.strain, label: String(format: "%.1f", w.strain), sublabel: "esfuerzo", size: 108)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.sport).font(Theme.display(28)).textCase(.uppercase)
                            Text(w.start.formatted(date: .abbreviated, time: .shortened)).font(Theme.body(13)).foregroundStyle(Theme.secondary)
                            Text(formatDuration(Int(w.end.timeIntervalSince(w.start)))).font(Theme.body(13)).foregroundStyle(Theme.secondary)
                        }
                    }
                }.appear()
                HStack(spacing: 8) {
                    StatTile(title: "Promedio", value: "\(w.avgHR)", unit: "lpm")
                    StatTile(title: "Máximo", value: "\(w.maxHR)", unit: "lpm")
                    StatTile(title: "Calorías", value: "\(w.kcal)", unit: "kcal")
                }.appear(0.05)
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Pulso")
                        Chart(Array(w.hrSeries.enumerated()).filter { $0.element > 0 }, id: \.offset) { i, hr in
                            LineMark(x: .value("Tiempo", Double(i) * 5 / 60), y: .value("lpm", hr))
                                .foregroundStyle(Theme.strain).interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxisLabel("minutos")
                        .frame(height: 160)
                    }
                }.appear(0.1)
                ZonesCard(minutes: w.zoneSeconds.map { $0 / 60 }).appear(0.15)
            } else {
                Text("Entrenamiento no encontrado").foregroundStyle(Theme.secondary)
            }
        }
        .navigationTitle("Entrenamiento")
        .navigationBarTitleDisplayMode(.inline)
    }
}
