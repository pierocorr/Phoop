import Foundation
import SwiftData

/// Métricas de un día: Recuperación, Esfuerzo y Sueño (fórmulas propias), más salud.
struct DayMetrics {
    var day: Date = Calendar.current.startOfDay(for: Date())

    // Sueño
    var sleep: SleepSession?
    var sleepPerformance: Double?        // 0…1
    var sleepNeedSeconds: Int = 8 * 3600
    var sleepDebtSeconds: Int = 0

    // Recuperación
    var recovery: Int?                   // 0…100
    var hrv: Int?
    var hrvBaseline: Int?
    var restingHR: Int?
    var restingHRBaseline: Int?
    var spo2: Int?
    var tempC: Double?
    var respiration: Int?

    // Últimas mediciones del día
    var latestHRV: Int?
    var latestSpO2: Int?
    var latestTemp: Double?
    var latestResp: Int?
    var latestBP: (Int, Int)?
    var latestTime: Date?

    var shownHRV: Int? { hrv ?? latestHRV }
    var shownSpO2: Int? { spo2 ?? latestSpO2 }
    var shownTemp: Double? { tempC ?? latestTemp }
    var shownResp: Int? { respiration ?? latestResp }

    // Estrés / energía
    var stress: Double?
    var stressSeries: [(Date, Double)] = []
    var energy: Double?
    var vo2max: Int?

    // Esfuerzo
    var strain: Double = 0               // 0…21
    var zoneMinutes: [Int] = [0, 0, 0, 0, 0]
    var hrToday: [(Date, Int)] = []
    var workouts: [Workout] = []

    // Actividad
    var steps: Int = 0
    var distanceM: Int = 0
    var kcal: Int = 0

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    var recoveryBand: RecoveryBand? {
        guard let r = recovery else { return nil }
        return r >= 67 ? .high : (r >= 34 ? .medium : .low)
    }

    var strainTarget: ClosedRange<Double> {
        switch recoveryBand {
        case .high: return 14...18
        case .medium, .none: return 10...13
        case .low: return 0...9
        }
    }

    var recommendation: String {
        switch recoveryBand {
        case .high: return "Recuperación alta. Tu cuerpo está listo para exigirse: apunta a un esfuerzo de 14–18."
        case .medium: return "Recuperación moderada. Un entrenamiento de intensidad media (esfuerzo 10–13) es lo ideal hoy."
        case .low: return "Recuperación baja. Prioriza descansar o moverte suave (esfuerzo 0–9) y dormir temprano."
        case .none: return "Duerme con la pulsera puesta para calcular tu recuperación de mañana."
        }
    }

    static func strainLabel(_ s: Double) -> String {
        switch s {
        case ..<10: return "Ligero"
        case ..<14: return "Moderado"
        case ..<18: return "Alto"
        default: return "Máximo"
        }
    }

    static func stressLabel(_ s: Double) -> String {
        switch s {
        case ..<30: return "Relajado"
        case ..<60: return "Normal"
        case ..<80: return "Medio"
        default: return "Alto"
        }
    }
}

enum RecoveryBand { case low, medium, high }

/// Hora sugerida para dormir.
struct SleepPlan {
    let wake: Date
    let options: [(label: String, bedtime: Date, hours: Double)]
}

@MainActor
enum MetricsEngine {

    /// Métricas del día `day` (hasta ahora si es hoy).
    static func compute(context: ModelContext, day: Date = Date()) -> DayMetrics {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
        let now = min(Date(), endOfDay)
        var m = DayMetrics()
        m.day = startOfDay
        m.sleepNeedSeconds = Int(Settings.sleepNeedHours * 3600)

        // --- Sueño: sesión que termina entre las 18:00 de ayer y el final del día
        let cutoff = startOfDay.addingTimeInterval(-6 * 3600)
        let sessions = (try? context.fetch(FetchDescriptor<SleepSession>(sortBy: [SortDescriptor(\.end, order: .reverse)]))) ?? []
        let lastNight = sessions.first { $0.end > cutoff && $0.end <= now && $0.start < endOfDay.addingTimeInterval(-6 * 3600) }
        m.sleep = lastNight
        if let s = lastNight {
            m.sleepPerformance = min(1, Double(s.asleepSeconds) / Double(max(1, m.sleepNeedSeconds)))
            m.sleepDebtSeconds = max(0, m.sleepNeedSeconds - s.asleepSeconds)
        }

        // --- Recuperación
        if let s = lastNight {
            let tonight = nightly(context: context, from: s.start, to: s.end)
            m.hrv = tonight.hrv
            m.restingHR = tonight.rhr
            m.spo2 = tonight.spo2
            m.tempC = tonight.temp
            m.respiration = tonight.resp

            let previous = sessions.filter { $0.end < s.start }.prefix(14)
            let past = previous.map { nightly(context: context, from: $0.start, to: $0.end) }
            let hrvs = past.compactMap { $0.hrv }
            let rhrs = past.compactMap { $0.rhr }
            m.hrvBaseline = hrvs.isEmpty ? nil : hrvs.reduce(0, +) / hrvs.count
            m.restingHRBaseline = rhrs.isEmpty ? nil : rhrs.reduce(0, +) / rhrs.count

            var score = 50.0
            if let h = m.hrv, let b = m.hrvBaseline, b > 0 { score += 60 * (Double(h) / Double(b) - 1) }
            if let r = m.restingHR, let b = m.restingHRBaseline { score += 2.5 * Double(b - r) }
            score += 40 * ((m.sleepPerformance ?? 0.85) - 0.85)
            m.recovery = Int(min(99, max(1, score.rounded())))
        }

        // --- Últimas mediciones del día
        var recent = FetchDescriptor<HealthSample>(predicate: #Predicate { $0.time >= startOfDay && $0.time < endOfDay },
                                                   sortBy: [SortDescriptor(\.time, order: .reverse)])
        recent.fetchLimit = 400
        let rs = (try? context.fetch(recent)) ?? []
        m.latestHRV = rs.first { $0.hrv > 0 }?.hrv
        m.latestSpO2 = rs.first { $0.spo2 > 0 }?.spo2
        m.latestTemp = rs.first { $0.tempC != nil }?.tempC
        m.latestResp = rs.first { $0.respiration > 0 }?.respiration
        if let bp = rs.first(where: { $0.sbp > 0 && $0.dbp > 0 }) { m.latestBP = (bp.sbp, bp.dbp) }
        m.latestTime = rs.first?.time

        // --- Estrés / energía
        let bodies = (try? context.fetch(FetchDescriptor<BodySample>(predicate: #Predicate { $0.time >= startOfDay && $0.time < endOfDay },
                                                                       sortBy: [SortDescriptor(\.time)]))) ?? []
        m.stressSeries = bodies.filter { $0.stress > 0 }.map { ($0.time, $0.stress) }
        m.stress = m.stressSeries.last?.1
        m.energy = bodies.last { $0.energy > 0 }?.energy
        m.vo2max = bodies.last { $0.vo2max > 0 }?.vo2max

        // --- Esfuerzo (TRIMP de Banister → escala 0–21)
        var points: [(Date, Int)] = []
        let hd = FetchDescriptor<HeartSample>(predicate: #Predicate { $0.time >= startOfDay && $0.time < endOfDay }, sortBy: [SortDescriptor(\.time)])
        points += ((try? context.fetch(hd)) ?? []).map { ($0.time, $0.bpm) }
        points += rs.filter { $0.bpm > 0 }.map { ($0.time, $0.bpm) }
        points.sort { $0.0 < $1.0 }
        m.hrToday = points

        let hrMax = Settings.hrMax
        let hrRest = Double(m.restingHR ?? 60)
        var trimp = 0.0
        for i in 0..<points.count {
            let next = i + 1 < points.count ? points[i + 1].0 : min(now, points[i].0.addingTimeInterval(60))
            let minutes = min(15, max(0, next.timeIntervalSince(points[i].0) / 60))
            let hr = Double(points[i].1)
            trimp += minutes * trimpWeight(hr: hr, rest: hrRest, max: hrMax)
            if let z = zone(hr: hr, max: hrMax) { m.zoneMinutes[z] += Int(minutes.rounded()) }
        }
        // Entrenamientos registrados (pulso cada 5 s, más preciso)
        m.workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.start >= startOfDay && $0.start < endOfDay },
                                                                    sortBy: [SortDescriptor(\.start, order: .reverse)]))) ?? []
        for w in m.workouts {
            for hr in w.hrSeries { trimp += (5.0 / 60) * trimpWeight(hr: Double(hr), rest: hrRest, max: hrMax) }
        }
        m.strain = strainFrom(trimp: trimp)

        // --- Actividad
        let acts = (try? context.fetch(FetchDescriptor<ActivityInterval>(predicate: #Predicate { $0.start >= startOfDay && $0.start < endOfDay }))) ?? []
        m.steps = acts.reduce(0) { $0 + $1.steps }
        m.distanceM = acts.reduce(0) { $0 + $1.distanceM }
        m.kcal = acts.reduce(0) { $0 + $1.kcal } + m.workouts.reduce(0) { $0 + $1.kcal }
        return m
    }

    static func trimpWeight(hr: Double, rest: Double, max: Double) -> Double {
        let hrr = Swift.max(0, Swift.min(1, (hr - rest) / Swift.max(1, max - rest)))
        return Settings.female ? hrr * 0.86 * exp(1.67 * hrr) : hrr * 0.64 * exp(1.92 * hrr)
    }

    static func strainFrom(trimp: Double) -> Double {
        (21 * (1 - exp(-trimp / 110)) * 10).rounded() / 10
    }

    /// Zona 0…4 (Z1…Z5) según % del pulso máximo.
    static func zone(hr: Double, max: Double) -> Int? {
        let pct = hr / max
        if pct >= 0.9 { return 4 }
        if pct >= 0.8 { return 3 }
        if pct >= 0.7 { return 2 }
        if pct >= 0.6 { return 1 }
        if pct >= 0.5 { return 0 }
        return nil
    }

    struct Nightly { var hrv: Int?; var rhr: Int?; var spo2: Int?; var temp: Double?; var resp: Int? }

    static func nightly(context: ModelContext, from: Date, to: Date) -> Nightly {
        var n = Nightly()
        let hs = (try? context.fetch(FetchDescriptor<HealthSample>(predicate: #Predicate { $0.time >= from && $0.time <= to }))) ?? []
        let hrvs = hs.map(\.hrv).filter { $0 > 0 }
        if !hrvs.isEmpty { n.hrv = hrvs.reduce(0, +) / hrvs.count }
        let sp = hs.map(\.spo2).filter { $0 > 0 }
        if !sp.isEmpty { n.spo2 = sp.reduce(0, +) / sp.count }
        let tp = hs.compactMap(\.tempC)
        if !tp.isEmpty { n.temp = (tp.reduce(0, +) / Double(tp.count) * 10).rounded() / 10 }
        let rs = hs.map(\.respiration).filter { $0 > 0 }
        if !rs.isEmpty { n.resp = rs.reduce(0, +) / rs.count }

        let heart = (try? context.fetch(FetchDescriptor<HeartSample>(predicate: #Predicate { $0.time >= from && $0.time <= to }))) ?? []
        let bpms = (heart.map(\.bpm) + hs.map(\.bpm)).filter { $0 > 30 }.sorted()
        if !bpms.isEmpty {
            let k = max(1, bpms.count / 10)
            n.rhr = bpms.prefix(k).reduce(0, +) / k
        }
        return n
    }

    // MARK: Tendencias

    struct TrendPoint: Identifiable { let id = UUID(); let day: Date; let value: Double }

    enum TrendMetric: String, CaseIterable, Identifiable {
        case recovery, strain, sleep, hrv, rhr, steps, spo2, stress
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recovery: return "Recuperación"
            case .strain: return "Esfuerzo"
            case .sleep: return "Horas de sueño"
            case .hrv: return "HRV"
            case .rhr: return "Pulso en reposo"
            case .steps: return "Pasos"
            case .spo2: return "SpO₂"
            case .stress: return "Estrés"
            }
        }
        var unit: String {
            switch self {
            case .recovery, .spo2: return "%"
            case .strain: return ""
            case .sleep: return "h"
            case .hrv: return "ms"
            case .rhr: return "lpm"
            case .steps: return "pasos"
            case .stress: return ""
            }
        }
    }

    /// Métricas de los últimos `days` días (del más antiguo al más reciente).
    static func history(context: ModelContext, days: Int) -> [DayMetrics] {
        let cal = Calendar.current
        return (0..<days).reversed().map { offset in
            compute(context: context, day: cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: Date())!))
        }
    }

    /// Serie diaria de una métrica.
    static func trend(_ metric: TrendMetric, from days: [DayMetrics]) -> [TrendPoint] {
        var out: [TrendPoint] = []
        for m in days {
            let day = m.day
            let v: Double?
            switch metric {
            case .recovery: v = m.recovery.map(Double.init)
            case .strain: v = m.strain > 0 ? m.strain : nil
            case .sleep: v = m.sleep.map { Double($0.asleepSeconds) / 3600 }
            case .hrv: v = m.shownHRV.map(Double.init)
            case .rhr: v = m.restingHR.map(Double.init)
            case .steps: v = m.steps > 0 ? Double(m.steps) : nil
            case .spo2: v = m.shownSpO2.map(Double.init)
            case .stress: v = m.stressSeries.isEmpty ? nil : m.stressSeries.map(\.1).reduce(0, +) / Double(m.stressSeries.count)
            }
            if let v { out.append(TrendPoint(day: day, value: v)) }
        }
        return out
    }

    // MARK: Entrenador de sueño

    static func sleepPlan(today: DayMetrics) -> SleepPlan {
        let cal = Calendar.current
        let wakeMin = Settings.wakeMinutes
        var wake = cal.date(bySettingHour: wakeMin / 60, minute: wakeMin % 60, second: 0, of: Date())!
        if wake < Date() { wake = cal.date(byAdding: .day, value: 1, to: wake)! }
        // Necesidad de esta noche: base + parte de la deuda + extra por esfuerzo alto.
        var needH = Settings.sleepNeedHours
        needH += min(2, Double(today.sleepDebtSeconds) / 3600) * 0.5
        if today.strain >= 14 { needH += 0.33 }
        if today.strain >= 18 { needH += 0.33 }
        let latency = 15.0 / 60
        let options: [(String, Double)] = [("Óptimo · 100 %", 1.0), ("Bueno · 85 %", 0.85), ("Mínimo · 70 %", 0.7)]
        return SleepPlan(wake: wake, options: options.map { label, f in
            let h = needH * f
            return (label, wake.addingTimeInterval(-(h + latency) * 3600), h)
        })
    }

    // MARK: Diario → impacto en la recuperación

    struct Insight: Identifiable { let id = UUID(); let behavior: JournalQuestion; let delta: Int; let samples: Int }

    static func journalInsights(context: ModelContext) -> [Insight] {
        let cal = Calendar.current
        let entries = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        guard entries.count >= 4 else { return [] }
        // Recuperación del día siguiente a cada entrada.
        var nextRecovery: [Date: Int] = [:]
        for e in entries {
            let next = cal.date(byAdding: .day, value: 1, to: e.day)!
            guard next <= Date() else { continue }
            if let r = compute(context: context, day: next).recovery { nextRecovery[e.day] = r }
        }
        var out: [Insight] = []
        for q in JournalQuestion.all {
            var yes: [Int] = [], no: [Int] = []
            for e in entries where e.answered.contains(q.id) {
                guard let r = nextRecovery[e.day] else { continue }
                if e.yes.contains(q.id) { yes.append(r) } else { no.append(r) }
            }
            guard yes.count >= 2, no.count >= 2 else { continue }
            let d = yes.reduce(0, +) / yes.count - no.reduce(0, +) / no.count
            out.append(Insight(behavior: q, delta: d, samples: yes.count + no.count))
        }
        return out.sorted { abs($0.delta) > abs($1.delta) }
    }
}

/// Preguntas del diario.
struct JournalQuestion: Identifiable, Hashable {
    let id: String
    let text: String
    let icon: String

    static let all: [JournalQuestion] = [
        .init(id: "alcohol", text: "¿Tomaste alcohol?", icon: "wineglass"),
        .init(id: "caffeine", text: "¿Cafeína después de las 2 p. m.?", icon: "cup.and.saucer"),
        .init(id: "screens", text: "¿Pantallas en la cama?", icon: "iphone"),
        .init(id: "lateMeal", text: "¿Cenaste tarde?", icon: "fork.knife"),
        .init(id: "stress", text: "¿Día muy estresante?", icon: "bolt.heart"),
        .init(id: "workout", text: "¿Entrenaste hoy?", icon: "figure.run"),
        .init(id: "meditation", text: "¿Meditaste o respiraste?", icon: "leaf"),
        .init(id: "nap", text: "¿Tomaste siesta?", icon: "bed.double"),
        .init(id: "water", text: "¿Te hidrataste bien?", icon: "drop"),
        .init(id: "reading", text: "¿Leíste antes de dormir?", icon: "book")
    ]
}
