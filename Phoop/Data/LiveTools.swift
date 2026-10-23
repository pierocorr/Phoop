import Foundation
import SwiftData
import Combine
import AVFoundation
import AudioToolbox
import Photos
import UIKit

/// Mediciones manuales (pulso, SpO₂, HRV, estrés, temperatura) desde la app.
/// El valor se muestra en vivo y se guarda al instante, sin esperar al historial.
@MainActor
final class MeasureManager: ObservableObject {
    static let shared = MeasureManager()

    @Published private(set) var running: YC.MeasureType?
    @Published private(set) var message: String?
    @Published private(set) var liveValue: String?
    private var bag = Set<AnyCancellable>()
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    // Últimos valores vistos durante la medición.
    private var bpm: Int?
    private var spo2: Int?
    private var hrv: Int?
    private var temp: Double?

    private init() {
        let band = BandManager.shared
        band.events.sink { [weak self] ev in
            guard let self else { return }
            switch ev {
            case let .measureResult(type, status):
                guard self.running?.rawValue == type else { return }
                if status == 1 { self.saveNow() }
                self.finish(status == 1 ? "Medición guardada" : (status == 2 ? "No se pudo medir. Ajusta la pulsera e inténtalo de nuevo." : "Medición cancelada"))
            case let .combined(c):
                guard self.running != nil else { return }
                if c.bpm > 0 { self.bpm = c.bpm }
                if let v = c.spo2, v > 0 { self.spo2 = v }
                if let v = c.hrv, v > 0 { self.hrv = v }
                if let v = c.tempC { self.temp = v }
                self.updateLive()
            default: break
            }
        }.store(in: &bag)
        band.heartSubject.sink { [weak self] v in
            guard let self, self.running != nil else { return }
            self.bpm = v
            self.updateLive()
        }.store(in: &bag)
    }

    private func updateLive() {
        guard let t = running else { return }
        switch t {
        case .heart: liveValue = bpm.map { "\($0) lpm" }
        case .spo2: liveValue = spo2.map { "\($0) %" }
        case .hrv: liveValue = hrv.map { "\($0) ms" }
        case .temp: liveValue = temp.map { String(format: "%.1f °C", $0) }
        case .stress: liveValue = nil
        }
    }

    func start(_ type: YC.MeasureType) {
        let band = BandManager.shared
        guard running == nil, band.state == .ready else {
            message = band.state == .ready ? nil : "Conecta la pulsera primero"
            return
        }
        running = type
        liveValue = nil
        bpm = nil; spo2 = nil; hrv = nil; temp = nil
        message = "Midiendo \(type.label.lowercased())… no muevas el brazo"
        band.send(YC.Cmd.measure(type, start: true))

        // Temperatura y SpO₂: pedir el valor actual cada 2 s para verlo al momento.
        if type == .temp || type == .spo2 {
            pollTask = Task { @MainActor in
                while !Task.isCancelled, self.running == type {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard self.running == type else { break }
                    if type == .temp, let p = await band.request(YC.Cmd.realTemp(), timeout: 1.5),
                       p.payload.count >= 2, p.payload[0] > 0 {
                        self.temp = Double("\(p.payload[0]).\(p.payload[1])")
                    }
                    if type == .spo2, let p = await band.request(YC.Cmd.realSpO2(), timeout: 1.5),
                       p.payload.count >= 2, p.payload[1] > 0 {
                        self.spo2 = Int(p.payload[1])
                    }
                    self.updateLive()
                }
            }
        }

        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            if self.running == type {
                band.send(YC.Cmd.measure(type, start: false))
                self.saveNow()
                self.finish("Medición terminada")
            }
        }
    }

    func stop() {
        guard let t = running else { return }
        BandManager.shared.send(YC.Cmd.measure(t, start: false))
        finish("Medición cancelada")
    }

    /// Guarda lo medido como una muestra nueva para que aparezca de inmediato en toda la app.
    private func saveNow() {
        guard let t = running, let ctx = SyncEngine.shared.container?.mainContext else { return }
        let hasValue = bpm != nil || spo2 != nil || hrv != nil || temp != nil
        if hasValue {
            let now = Date()
            ctx.insert(HealthSample(time: now, bpm: bpm ?? 0, hrv: hrv ?? 0, spo2: spo2 ?? 0,
                                    respiration: 0, tempC: temp, steps: 0))
            if let b = bpm { ctx.insert(HeartSample(time: now, bpm: b, live: true)) }
            try? ctx.save()
            SyncEngine.shared.bump()
        }
        // Además, descargar el historial de la pulsera (por ejemplo, el estrés).
        Task { await SyncEngine.shared.syncKinds([t.history]) }
    }

    private func finish(_ text: String) {
        timeoutTask?.cancel()
        pollTask?.cancel()
        running = nil
        message = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.running == nil { self.message = nil }
        }
    }
}

/// Prueba de ECG en vivo.
@MainActor
final class ECGManager: ObservableObject {
    static let shared = ECGManager()
    static let duration: TimeInterval = 30

    @Published private(set) var recording = false
    @Published private(set) var display: [Int] = []      // últimas muestras para dibujar
    @Published private(set) var progress: Double = 0
    @Published private(set) var bpm: Int?
    @Published private(set) var lastResult: String?

    private var all: [Int] = []
    private var hrs: [Int] = []
    private var started = Date()
    private var bag = Set<AnyCancellable>()
    private var timer: Timer?

    private init() {
        let band = BandManager.shared
        band.events.sink { [weak self] ev in
            guard let self, self.recording, case let .ecg(s) = ev else { return }
            self.all.append(contentsOf: s)
            self.display.append(contentsOf: s)
            if self.display.count > 1200 { self.display.removeFirst(self.display.count - 1200) }
        }.store(in: &bag)
        band.heartSubject.sink { [weak self] v in
            guard let self, self.recording else { return }
            self.hrs.append(v)
            self.bpm = v
        }.store(in: &bag)
    }

    func start() {
        guard !recording, BandManager.shared.state == .ready else { return }
        all = []; hrs = []; display = []; bpm = nil; progress = 0; lastResult = nil
        recording = true
        started = Date()
        BandManager.shared.send(YC.Cmd.ecg(start: true))
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in ECGManager.shared.tickProgress() }
        }
    }

    private func tickProgress() {
        progress = min(1, Date().timeIntervalSince(started) / Self.duration)
        if progress >= 1, let ctx = SyncEngine.shared.container?.mainContext { stop(context: ctx) }
    }

    func stop(context: ModelContext) {
        guard recording else { return }
        recording = false
        timer?.invalidate()
        BandManager.shared.send(YC.Cmd.ecg(start: false))
        let secs = Int(Date().timeIntervalSince(started))
        guard all.count > 100 else {
            lastResult = "No llegaron datos de ECG. Toca el electrodo de la pulsera con el dedo de la otra mano durante la prueba."
            return
        }
        let avg = hrs.isEmpty ? 0 : hrs.reduce(0, +) / hrs.count
        // Guardar como máximo ~8 000 muestras.
        let step = max(1, all.count / 8000)
        let kept = stride(from: 0, to: all.count, by: step).map { all[$0] }
        context.insert(ECGRecord(time: started, seconds: secs, bpm: avg, samples: kept))
        try? context.save()
        lastResult = avg > 0 ? "ECG guardado · pulso promedio \(avg) lpm" : "ECG guardado"
        SyncEngine.shared.bump()
    }
}

/// Eventos de la pulsera que necesitan al teléfono: buscar el teléfono.
@MainActor
final class PhoneFinder: ObservableObject {
    static let shared = PhoneFinder()
    @Published var ringing = false
    private var bag = Set<AnyCancellable>()
    private var task: Task<Void, Never>?

    private init() {
        BandManager.shared.events.sink { [weak self] ev in
            if case .findPhone = ev { self?.ring() }
        }.store(in: &bag)
    }

    func ring() {
        ringing = true
        task?.cancel()
        task = Task { @MainActor in
            for _ in 0..<10 {
                guard self.ringing else { break }
                AudioServicesPlayAlertSound(SystemSoundID(1005))
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            self.ringing = false
        }
    }

    func stop() { ringing = false; task?.cancel() }
}

/// Cámara remota: la pulsera dispara la foto.
@MainActor
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var lastSaved = false
    @Published var flash = false
    @Published var denied = false
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var bag = Set<AnyCancellable>()

    override init() {
        super.init()
        BandManager.shared.events.sink { [weak self] ev in
            if case .takePhoto = ev { self?.capture() }
        }.store(in: &bag)
    }

    func open() {
        BandManager.shared.send(YC.Cmd.cameraMode(true))
        Task {
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            guard ok else { denied = true; return }
            if !configured { configure() }
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { if !s.isRunning { s.startRunning() } }
        }
    }

    func close() {
        BandManager.shared.send(YC.Cmd.cameraMode(false))
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { if s.isRunning { s.stopRunning() } }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    func capture() {
        guard session.isRunning else { return }
        flash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.flash = false
        }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            } completionHandler: { ok, _ in
                Task { @MainActor in self.lastSaved = ok }
            }
        }
    }
}
