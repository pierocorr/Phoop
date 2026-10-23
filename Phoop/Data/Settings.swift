import Foundation

/// Ajustes del usuario (guardados en el iPhone).
enum Settings {
    static let stepGoalKey = "stepGoal"
    static let ageKey = "age"
    static let weightKey = "weightKg"
    static let heightKey = "heightCm"
    static let femaleKey = "female"
    static let sleepNeedKey = "sleepNeedHours"
    static let healthSyncKey = "healthSync"
    static let deleteAfterSyncKey = "deleteAfterSync"
    static let heartIntervalKey = "heartInterval"
    static let lastSyncKey = "lastSync"

    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            stepGoalKey: 11000,
            ageKey: 25,
            weightKey: 70,
            heightKey: 170,
            femaleKey: false,
            sleepNeedKey: 8.0,
            healthSyncKey: true,
            deleteAfterSyncKey: false,
            heartIntervalKey: 10
        ])
    }

    static var stepGoal: Int { d.integer(forKey: stepGoalKey) }
    static var age: Int { d.integer(forKey: ageKey) }
    static var weightKg: Int { d.integer(forKey: weightKey) }
    static var heightCm: Int { d.integer(forKey: heightKey) }
    static var female: Bool { d.bool(forKey: femaleKey) }
    static var sleepNeedHours: Double { d.double(forKey: sleepNeedKey) }
    static var healthSync: Bool { d.bool(forKey: healthSyncKey) }
    static var deleteAfterSync: Bool { d.bool(forKey: deleteAfterSyncKey) }
    static var heartInterval: Int { d.integer(forKey: heartIntervalKey) }
    static var lastSync: Date? {
        get { d.object(forKey: lastSyncKey) as? Date }
        set { d.set(newValue, forKey: lastSyncKey) }
    }
}
