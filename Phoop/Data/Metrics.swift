import Foundation
import SwiftData

/// Cálculo propio de Recuperación, Esfuerzo y Sueño (inspirado en la idea de Whoop,
/// pero con fórmulas propias y documentadas).
struct DayMetrics {
    // Sueño
    var sleep: SleepSession?
    var sleepPerformance: Double?        // 0…1
    var sleepNeedSeconds: Int = 8 * 3600
    var sleepDebtSeconds: Int = 0

    // Recuperación
    var recovery: Int?                   // 0…100
    var hrv: Int?                        // ms (noche)
    var hrvBaseline: Int?
    var restingHR: Int?
    var restingHRBaseline: Int?
    var spo2: Int?
    var tempC: Double?
    var respiration: Int?

    // Última medición del día (aunque no haya noche registrada)
    var latestHRV: Int?
    var latestSpO2: Int?
    var latestTemp: Double?
    var latestResp: Int?
    var latestTime: Date?

    var shownHRV: Int? { hrv ?? latestHRV }
    var shownSpO2: Int? { spo2 ?? latestSpO2 }
    var shownTemp: Double? { tempC ?? latestTemp }

    // Esfuerzo
    var strain: Double = 0               // 0…21
    var zoneMinutes: [Int] = [0, 0, 0, 0, 0] // Z1…Z5
    var hrToday: [(Date, Int)] = []

    // Actividad
    var steps: Int = 0
    var distanceM: Int = 0
    var kcal: Int = 0

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
        case .none: return "Usa la pulsera esta noche para calcular tu primera recuperación."
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
}

enum RecoveryBand { case low, medium, high }

@MainActor
enum MetricsEngine {

    static func compute(context: ModelContext, now: Date = Date()) -> DayMetrics {
        var m = DayMetrics()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        m.sleepNeedSeconds = Int(Settings.sleepNeedHours * 3600)

        // --- Sueño: la sesión más reciente que termina después de las 18:00 de ayer
        let cutoff = startOfDay.addingTimeInterval(-6 * 3600)
        let sessions = (try? context.fetch(FetchDescriptor<SleepSession>(sortBy: [SortDescriptor(\.end, order: .reverse)]))) ?? []
        let lastNight = sessions.first { $0.end > cutoff && $0.end <= now }
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

        // --- Esfuerzo (TRIMP de Banister → escala 0–21)
        var points: [(Date, Int)] = []
        let hd = FetchDescriptor<HeartSample>(predicate: #Predicate { $0.time >= startOfDay }, sortBy: [SortDescriptor(\.time)])
        points += ((try? context.fetch(hd)) ?? []).map { ($0.time, $0.bpm) }
        let ad = FetchDescriptor<HealthSample>(predicate: #Predicate { $0.time >= startOfDay }, sortBy: [SortDescriptor(\.time)])
        points += ((try? context.fetch(ad)) ?? []).filter { $0.bpm > 0 }.map { ($0.time, $0.bpm) }
        points.sort { $0.0 < $1.0 }
        m.hrToday = points

        let age = Double(Settings.age)
        let hrMax = 208 - 0.7 * age
        let hrRest = Double(m.restingHR ?? 60)
        let female = Settings.female
        var trimp = 0.0
        for i in 0..<points.count {
            let next = i + 1 < points.count ? points[i + 1].0 : min(now, points[i].0.addingTimeInterval(60))
            let minutes = min(15, max(0, next.timeIntervalSince(points[i].0) / 60))
            let hr = Double(points[i].1)
            let hrr = max(0, min(1, (hr - hrRest) / max(1, hrMax - hrRest)))
            trimp += minutes * hrr * (female ? 0.86 * exp(1.67 * hrr) : 0.64 * exp(1.92 * hrr))
            let pct = hr / hrMax
            let zone: Int? = pct >= 0.9 ? 4 : pct >= 0.8 ? 3 : pct >= 0.7 ? 2 : pct >= 0.6 ? 1 : pct >= 0.5 ? 0 : nil
            if let z = zone { m.zoneMinutes[z] += Int(minutes.rounded()) }
        }
        m.strain = (21 * (1 - exp(-trimp / 110)) * 10).rounded() / 10

        // --- Últimas mediciones (24 h)
        let dayAgo = now.addingTimeInterval(-86400)
        var recent = FetchDescriptor<HealthSample>(predicate: #Predicate { $0.time >= dayAgo && $0.time <= now },
                                                   sortBy: [SortDescriptor(\.time, order: .reverse)])
        recent.fetchLimit = 300
        let rs = (try? context.fetch(recent)) ?? []
        m.latestHRV = rs.first { $0.hrv > 0 }?.hrv
        m.latestSpO2 = rs.first { $0.spo2 > 0 }?.spo2
        m.latestTemp = rs.first { $0.tempC != nil }?.tempC
        m.latestResp = rs.first { $0.respiration > 0 }?.respiration
        m.latestTime = rs.first?.time

        // --- Actividad de hoy
        let acts = (try? context.fetch(FetchDescriptor<ActivityInterval>(predicate: #Predicate { $0.start >= startOfDay }))) ?? []
        m.steps = acts.reduce(0) { $0 + $1.steps }
        m.distanceM = acts.reduce(0) { $0 + $1.distanceM }
        m.kcal = acts.reduce(0) { $0 + $1.kcal }
        return m
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
            // Pulso en reposo: promedio del 10 % más bajo de la noche.
            let k = max(1, bpms.count / 10)
            n.rhr = bpms.prefix(k).reduce(0, +) / k
        }
        return n
    }

    /// Recuperación de los últimos 7 días (para el gráfico).
    static func recoveryHistory(context: ModelContext, days: Int = 7) -> [(Date, Int?)] {
        let cal = Calendar.current
        return (0..<days).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: Date())!
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            return (day, compute(context: context, now: noon).recovery)
        }
    }
}
