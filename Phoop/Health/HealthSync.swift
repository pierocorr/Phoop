import Foundation
import HealthKit
import SwiftData

/// Exporta automáticamente los datos de la pulsera a Apple Salud.
/// Cada muestra lleva un identificador de sincronización, así Salud nunca la duplica.
@MainActor
final class HealthSync {
    static let shared = HealthSync()
    private let store = HKHealthStore()

    private var shareTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = [HKCategoryType(.sleepAnalysis)]
        let q: [HKQuantityTypeIdentifier] = [.heartRate, .heartRateVariabilitySDNN, .oxygenSaturation,
                                             .respiratoryRate, .bodyTemperature, .stepCount,
                                             .distanceWalkingRunning, .activeEnergyBurned]
        q.forEach { s.insert(HKQuantityType($0)) }
        return s
    }

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard available else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [])
            return true
        } catch {
            return false
        }
    }

    /// Exporta lo de los últimos `days` días.
    func export(context: ModelContext, days: Int = 3) async -> Int {
        guard Settings.healthSync, available else { return 0 }
        _ = await requestAuthorization()
        let since = Date().addingTimeInterval(-Double(days) * 86400)
        var samples: [HKSample] = []
        let device = HKDevice(name: BandManager.shared.deviceName, manufacturer: "Loop Life", model: "SOOP",
                              hardwareVersion: nil, firmwareVersion: BandManager.shared.firmware,
                              softwareVersion: nil, localIdentifier: nil, udiDeviceIdentifier: nil)

        func meta(_ id: String) -> [String: Any] {
            [HKMetadataKeySyncIdentifier: "phoop.\(id)", HKMetadataKeySyncVersion: 1]
        }
        func quantity(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ v: Double, _ start: Date, _ end: Date? = nil, key: String) {
            let type = HKQuantityType(id)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { return }
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: v),
                                            start: start, end: end ?? start, device: device, metadata: meta(key)))
        }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        // Pulso
        let heart = (try? context.fetch(FetchDescriptor<HeartSample>(predicate: #Predicate { $0.time >= since }))) ?? []
        for h in heart { quantity(.heartRate, bpmUnit, Double(h.bpm), h.time, key: "hr.\(Int(h.time.timeIntervalSince1970))") }

        // HRV, SpO₂, respiración, temperatura
        let hs = (try? context.fetch(FetchDescriptor<HealthSample>(predicate: #Predicate { $0.time >= since }))) ?? []
        for s in hs {
            let t = Int(s.time.timeIntervalSince1970)
            if s.bpm > 0 { quantity(.heartRate, bpmUnit, Double(s.bpm), s.time, key: "hr2.\(t)") }
            if s.hrv > 0 { quantity(.heartRateVariabilitySDNN, .secondUnit(with: .milli), Double(s.hrv), s.time, key: "hrv.\(t)") }
            if s.spo2 > 0 { quantity(.oxygenSaturation, .percent(), Double(s.spo2) / 100, s.time, key: "spo2.\(t)") }
            if s.respiration > 0 { quantity(.respiratoryRate, bpmUnit, Double(s.respiration), s.time, key: "resp.\(t)") }
            if let c = s.tempC { quantity(.bodyTemperature, .degreeCelsius(), c, s.time, key: "temp.\(t)") }
        }

        // Pasos, distancia, calorías
        let acts = (try? context.fetch(FetchDescriptor<ActivityInterval>(predicate: #Predicate { $0.start >= since }))) ?? []
        for a in acts where a.end > a.start {
            let t = Int(a.start.timeIntervalSince1970)
            if a.steps > 0 { quantity(.stepCount, .count(), Double(a.steps), a.start, a.end, key: "steps.\(t)") }
            if a.distanceM > 0 { quantity(.distanceWalkingRunning, .meter(), Double(a.distanceM), a.start, a.end, key: "dist.\(t)") }
            if a.kcal > 0 { quantity(.activeEnergyBurned, .kilocalorie(), Double(a.kcal), a.start, a.end, key: "kcal.\(t)") }
        }

        // Sueño con fases
        let sleepType = HKCategoryType(.sleepAnalysis)
        if store.authorizationStatus(for: sleepType) == .sharingAuthorized {
            let sessions = (try? context.fetch(FetchDescriptor<SleepSession>(predicate: #Predicate { $0.end >= since }))) ?? []
            for s in sessions {
                let t = Int(s.start.timeIntervalSince1970)
                samples.append(HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                                                start: s.start, end: s.end, device: device, metadata: meta("inbed.\(t)")))
                for st in s.stages where st.seconds > 0 {
                    let value: HKCategoryValueSleepAnalysis
                    switch st.stage {
                    case .deep: value = .asleepDeep
                    case .light: value = .asleepCore
                    case .rem: value = .asleepREM
                    case .awake: value = .awake
                    case .none: value = .asleepUnspecified
                    }
                    samples.append(HKCategorySample(type: sleepType, value: value.rawValue, start: st.start, end: st.end,
                                                    device: device, metadata: meta("sleep.\(Int(st.start.timeIntervalSince1970))")))
                }
            }
        }

        guard !samples.isEmpty else { return 0 }
        do {
            try await store.save(samples)
            return samples.count
        } catch {
            return 0
        }
    }
}
