import Foundation
import SwiftData
import Combine
import HealthKit

enum SportType: String, CaseIterable, Identifiable {
    case running = "Correr", walking = "Caminar", cycling = "Ciclismo", strength = "Pesas",
         hiit = "HIIT", soccer = "Fútbol", yoga = "Yoga", other = "Otro"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .strength: return "dumbbell.fill"
        case .hiit: return "flame.fill"
        case .soccer: return "soccerball"
        case .yoga: return "figure.yoga"
        case .other: return "figure.mixed.cardio"
        }
    }

    var hkType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .strength: return .traditionalStrengthTraining
        case .hiit: return .highIntensityIntervalTraining
        case .soccer: return .soccer
        case .yoga: return .yoga
        case .other: return .other
        }
    }
}

/// Entrenamiento en vivo: pulso continuo, esfuerzo, zonas y calorías.
@MainActor
final class WorkoutManager: ObservableObject {
    static let shared = WorkoutManager()

    @Published private(set) var active = false
    @Published private(set) var sport: SportType = .running
    @Published private(set) var start = Date()
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var hr: Int?
    @Published private(set) var strain: Double = 0
    @Published private(set) var kcal: Double = 0
    @Published private(set) var zoneSeconds = [0, 0, 0, 0, 0]
    @Published private(set) var series: [Int] = []

    private var lastHR: Int?
    private var lastHRTime = Date.distantPast
    private var trimp = 0.0
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    private init() {
        BandManager.shared.heartSubject
            .sink { [weak self] bpm in
                self?.lastHR = bpm
                self?.lastHRTime = Date()
            }
            .store(in: &bag)
    }

    var currentZone: Int? { hr.flatMap { MetricsEngine.zone(hr: Double($0), max: Settings.hrMax) } }

    func begin(_ sport: SportType) {
        guard !active else { return }
        self.sport = sport
        start = Date()
        elapsed = 0; strain = 0; kcal = 0; trimp = 0
        zoneSeconds = [0, 0, 0, 0, 0]
        series = []
        active = true
        let band = BandManager.shared
        band.send(YC.Cmd.realtime(true))
        band.send(YC.Cmd.measure(.heart, start: true))
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in WorkoutManager.shared.tick() }
        }
    }

    private func tick() {
        guard active else { return }
        elapsed = Date().timeIntervalSince(start)
        // Si la pulsera dejó de enviar pulso, pedir otra medición.
        if Date().timeIntervalSince(lastHRTime) > 20 {
            BandManager.shared.send(YC.Cmd.measure(.heart, start: true))
        }
        let current = Date().timeIntervalSince(lastHRTime) < 30 ? lastHR : nil
        hr = current
        series.append(current ?? 0)
        guard let bpm = current else { return }
        let rest = 60.0
        trimp += (5.0 / 60) * MetricsEngine.trimpWeight(hr: Double(bpm), rest: rest, max: Settings.hrMax)
        strain = MetricsEngine.strainFrom(trimp: trimp)
        if let z = MetricsEngine.zone(hr: Double(bpm), max: Settings.hrMax) { zoneSeconds[z] += 5 }
        kcal += (5.0 / 60) * Self.kcalPerMinute(hr: Double(bpm))
    }

    /// Fórmula de Keytel (2005) para gasto energético según pulso.
    static func kcalPerMinute(hr: Double) -> Double {
        let w = Double(Settings.weightKg), a = Double(Settings.age)
        let v = Settings.female
            ? (-20.4022 + 0.4472 * hr - 0.1263 * w + 0.074 * a) / 4.184
            : (-55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a) / 4.184
        return max(0, v)
    }

    @discardableResult
    func finish(context: ModelContext) -> Workout? {
        guard active else { return nil }
        active = false
        timer?.invalidate()
        let band = BandManager.shared
        band.send(YC.Cmd.measure(.heart, start: false))
        band.send(YC.Cmd.realtime(false))
        let valid = series.filter { $0 > 0 }
        guard elapsed >= 60, !valid.isEmpty else { return nil }
        let w = Workout(start: start, end: Date(), sport: sport.rawValue,
                        avgHR: valid.reduce(0, +) / valid.count, maxHR: valid.max() ?? 0,
                        strain: strain, kcal: Int(kcal.rounded()), zoneSeconds: zoneSeconds, hrSeries: series)
        context.insert(w)
        try? context.save()
        let s = sport
        Task { await HealthSync.shared.exportWorkout(w, sport: s) }
        SyncEngine.shared.bump()
        return w
    }

    func cancel() {
        active = false
        timer?.invalidate()
        BandManager.shared.send(YC.Cmd.measure(.heart, start: false))
        BandManager.shared.send(YC.Cmd.realtime(false))
    }
}
