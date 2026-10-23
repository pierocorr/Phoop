import Foundation
import SwiftData
import Combine
import BackgroundTasks

/// Descarga el historial de la pulsera, lo guarda y lo exporta a Apple Salud.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()
    static let bgTaskID = "com.phoop.app.sync"

    @Published private(set) var syncing = false
    @Published private(set) var status = ""
    @Published private(set) var lastSync: Date? = Settings.lastSync
    @Published private(set) var revision = 0   // cambia cada vez que hay datos nuevos

    var container: ModelContainer!
    private var bag = Set<AnyCancellable>()
    private var lastLiveSave = Date.distantPast
    private var timer: Timer?
    private var settingsPushed = false

    func attach(_ container: ModelContainer) {
        self.container = container
        let band = BandManager.shared

        // Guardar el pulso en vivo (una muestra por minuto).
        band.heartSubject
            .sink { [weak self] bpm in self?.saveLive(bpm) }
            .store(in: &bag)

        // Sincronizar cada vez que la pulsera queda lista.
        band.$state
            .removeDuplicates()
            .filter { $0 == .ready }
            .sink { [weak self] _ in Task { await self?.sync() } }
            .store(in: &bag)

        // Al terminar una medición manual, descargar ese historial.
        band.events
            .sink { [weak self] ev in
                if case let .measureResult(type, status) = ev, status == 1,
                   let t = YC.MeasureType(rawValue: type) {
                    Task { await self?.syncKinds([t.history]) }
                }
            }
            .store(in: &bag)

        // Y cada 30 minutos mientras siga conectada.
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            Task { @MainActor in
                if BandManager.shared.state == .ready { await SyncEngine.shared.sync() }
            }
        }
    }

    func bump() { revision += 1 }

    private func saveLive(_ bpm: Int) {
        guard let container, Date().timeIntervalSince(lastLiveSave) >= 60 else { return }
        lastLiveSave = Date()
        let ctx = container.mainContext
        let minute = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60)
        ctx.insert(HeartSample(time: minute, bpm: bpm, live: true))
        try? ctx.save()
        revision += 1
    }

    /// Sincronización completa. Segura de llamar varias veces.
    @discardableResult
    func sync() async -> Bool {
        guard !syncing, container != nil else { return false }
        syncing = true
        defer { syncing = false }
        let band = BandManager.shared

        status = "Conectando…"
        guard await band.waitUntilReady() else {
            status = "No se encontró la pulsera"
            return false
        }

        if !settingsPushed {
            status = "Enviando ajustes…"
            await pushSettings()
            settingsPushed = true
        }

        let newItems = await fetch(YC.HistoryKind.allCases)
        await band.refreshDeviceInfo()

        if Settings.healthSync {
            status = "Enviando a Apple Salud…"
            _ = await HealthSync.shared.export(context: container.mainContext)
        }

        lastSync = Date()
        Settings.lastSync = lastSync
        status = newItems > 0 ? "Sincronizado · \(newItems) registros" : "Sincronizado"
        revision += 1
        Self.scheduleBackground()
        return true
    }

    /// Descarga solo algunos historiales (p. ej. tras una medición manual).
    func syncKinds(_ kinds: [YC.HistoryKind]) async {
        guard !syncing, BandManager.shared.state == .ready else { return }
        syncing = true
        defer { syncing = false }
        _ = await fetch(kinds)
        if Settings.healthSync { _ = await HealthSync.shared.export(context: container.mainContext, days: 1) }
        revision += 1
    }

    private func fetch(_ kinds: [YC.HistoryKind]) async -> Int {
        let band = BandManager.shared
        let ctx = container.mainContext
        var newItems = 0
        for kind in kinds {
            status = "Descargando \(kind.label)…"
            guard let bytes = await band.fetchHistory(kind) else { continue }
            switch kind {
            case .sport:
                for r in YC.parseSport(bytes) where r.steps > 0 || r.kcal > 0 {
                    ctx.insert(ActivityInterval(start: r.start, end: r.end, steps: r.steps, distanceM: r.distanceM, kcal: r.kcal))
                    newItems += 1
                }
            case .sleep:
                for r in YC.parseSleep(bytes) where r.end > r.start {
                    let stages = r.stages.map { StoredStage(type: $0.type, start: $0.start, seconds: $0.seconds) }
                    ctx.insert(SleepSession(start: r.start, end: r.end, stages: stages))
                    newItems += 1
                }
            case .heart:
                for r in YC.parseHeart(bytes) {
                    ctx.insert(HeartSample(time: r.time, bpm: r.bpm))
                    newItems += 1
                }
            case .all:
                for r in YC.parseAll(bytes) {
                    ctx.insert(HealthSample(time: r.time, bpm: r.bpm, hrv: r.hrv, spo2: r.spo2,
                                            respiration: r.respiration, tempC: r.tempC, steps: r.steps,
                                            sbp: r.sbp, dbp: r.dbp))
                    newItems += 1
                }
            case .body:
                for r in YC.parseBody(bytes) {
                    ctx.insert(BodySample(r))
                    newItems += 1
                }
            }
            try? ctx.save()
            if Settings.deleteAfterSync, !bytes.isEmpty {
                _ = await band.request(YC.Cmd.deleteHistory(kind), timeout: 3)
            }
        }
        return newItems
    }

    /// Enviar ajustes a la pulsera (meta de pasos, datos de usuario, monitoreo, alarma).
    func pushSettings() async {
        let band = BandManager.shared
        guard band.state == .ready else { return }
        _ = await band.request(YC.Cmd.stepGoal(Settings.stepGoal))
        _ = await band.request(YC.Cmd.userInfo(heightCm: Settings.heightCm, weightKg: Settings.weightKg,
                                               female: Settings.female, age: Settings.age))
        _ = await band.request(YC.Cmd.heartMonitor(on: true, minutes: Settings.heartInterval))
        _ = await band.request(YC.Cmd.tempMonitor(on: true, minutes: Settings.heartInterval))
        _ = await band.request(YC.Cmd.spo2Monitor(on: true, minutes: max(30, Settings.heartInterval)))
        _ = await band.request(YC.Cmd.heartAlarm(on: Settings.heartAlarmOn, max: Settings.heartAlarmMax))
    }

    // MARK: Segundo plano

    static func registerBackground() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            scheduleBackground()
            let work = Task { @MainActor in
                let ok = await SyncEngine.shared.sync()
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleBackground() {
        let req = BGAppRefreshTaskRequest(identifier: bgTaskID)
        req.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
