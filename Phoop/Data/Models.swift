import Foundation
import SwiftData

/// Muestra de pulso (historial de la pulsera o pulso en vivo, 1 por minuto).
@Model
final class HeartSample {
    @Attribute(.unique) var time: Date
    var bpm: Int
    var live: Bool

    init(time: Date, bpm: Int, live: Bool = false) {
        self.time = time
        self.bpm = bpm
        self.live = live
    }
}

/// Registro "completo" de la pulsera: HRV, SpO₂, temperatura, respiración.
@Model
final class HealthSample {
    @Attribute(.unique) var time: Date
    var bpm: Int
    var hrv: Int
    var spo2: Int
    var respiration: Int
    var tempC: Double?
    var steps: Int

    init(time: Date, bpm: Int, hrv: Int, spo2: Int, respiration: Int, tempC: Double?, steps: Int) {
        self.time = time
        self.bpm = bpm
        self.hrv = hrv
        self.spo2 = spo2
        self.respiration = respiration
        self.tempC = tempC
        self.steps = steps
    }
}

/// Intervalo de actividad (pasos, distancia, calorías).
@Model
final class ActivityInterval {
    @Attribute(.unique) var start: Date
    var end: Date
    var steps: Int
    var distanceM: Int
    var kcal: Int

    init(start: Date, end: Date, steps: Int, distanceM: Int, kcal: Int) {
        self.start = start
        self.end = end
        self.steps = steps
        self.distanceM = distanceM
        self.kcal = kcal
    }
}

enum SleepStageType: Int, Codable, CaseIterable {
    case deep = 241, light = 242, rem = 243, awake = 244

    var label: String {
        switch self {
        case .deep: return "Profundo"
        case .light: return "Ligero"
        case .rem: return "REM"
        case .awake: return "Despierto"
        }
    }
}

struct StoredStage: Codable, Hashable {
    var type: Int
    var start: Date
    var seconds: Int
    var stage: SleepStageType? { SleepStageType(rawValue: type) }
    var end: Date { start.addingTimeInterval(TimeInterval(seconds)) }
}

/// Una noche de sueño con sus fases.
@Model
final class SleepSession {
    @Attribute(.unique) var start: Date
    var end: Date
    var stages: [StoredStage]

    init(start: Date, end: Date, stages: [StoredStage]) {
        self.start = start
        self.end = end
        self.stages = stages
    }

    func seconds(_ t: SleepStageType) -> Int {
        stages.filter { $0.type == t.rawValue }.reduce(0) { $0 + $1.seconds }
    }

    var asleepSeconds: Int {
        let s = stages.filter { $0.type != SleepStageType.awake.rawValue }.reduce(0) { $0 + $1.seconds }
        return s > 0 ? s : Int(end.timeIntervalSince(start))
    }

    var wakeCount: Int { stages.filter { $0.type == SleepStageType.awake.rawValue }.count }
}

enum PhoopSchema {
    static let models: [any PersistentModel.Type] = [HeartSample.self, HealthSample.self, ActivityInterval.self, SleepSession.self]
}
