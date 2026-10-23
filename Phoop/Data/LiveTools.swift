import Foundation
import SwiftData
import Combine
import AVFoundation
import AudioToolbox
import Photos
import UIKit

/// Mediciones manuales (pulso, SpO₂, HRV, estrés, temperatura) desde la app.
@MainActor
final class MeasureManager: ObservableObject {
    static let shared = MeasureManager()

    @Published private(set) var running: YC.MeasureType?
    @Published private(set) var message: String?
    @Published private(set) var liveValue: String?
    private var bag = Set<AnyCancellable>()
    private var timeoutTask: Task<Void, Never>?

    private init() {
        let band = BandManager.shared
        band.events.sink { [weak self] ev in
            guard let self else { return }
            switch ev {
            case let .measureResult(type, status):
                guard self.running?.rawValue == type else { return }
                self.finish(status == 1 ? "Medición guardada" : (status == 2 ? "No se pudo medir. Ajusta la pulsera e inténtalo de nuevo." : "Medición cancelada"))
            case let .combined(c):
                guard let t = self.running else { return }
                switch t {
                case .heart: if c.bpm > 0 { self.liveValue = "\(c.bpm) lpm" }
                case .spo2: if let v = c.spo2, v > 0 { self.liveValue = "\(v) %" }
                case .hrv: if let v = c.hrv, v > 0 { self.liveValue = "\(v) ms" }
                case .temp: if let v = c.tempC { self.liveValue = String(format: "%.1f °C", v) }
                case .stress: break
                }
            default: break
            }
        }.store(in: &bag)
        band.heartSubject.sink { [weak self] bpm in
            if self?.running == .heart { self?.liveValue = "\(bpm) lpm" }
        }.store(in: &bag)
    }

    func start(_ type: YC.MeasureType) {
        guard running == nil, BandManager.shared.state == .ready else {
            message = BandManager.shared.state == .ready ? nil : "Conecta la pulsera primero"
            return
        }
        running = type
        liveValue = nil
        message = "Midiendo \(type.label.lowercased())… no muevas el brazo"
        BandManager.shared.send(YC.Cmd.measure(type, start: true))
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            if self.running == type {
                BandManager.shared.send(YC.Cmd.measure(type, start: false))
                await SyncEngine.shared.syncKinds([type.history])
                self.finish("Medición terminada")
            }
        }
    }

    func stop() {
        guard let t = running else { return }
        BandManager.shared.send(YC.Cmd.measure(t, start: false))
        finish("Medición cancelada")
    }

    private func finish(_ text: String) {
        timeoutTask?.cancel()
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
