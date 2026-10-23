import SwiftUI
import SwiftData
import AVFoundation

struct MoreView: View {
    @EnvironmentObject private var band: BandManager
    @EnvironmentObject private var sync: SyncEngine

    @AppStorage(Settings.stepGoalKey) private var stepGoal = 11000
    @AppStorage(Settings.heartIntervalKey) private var heartInterval = 10
    @AppStorage(Settings.healthSyncKey) private var healthSync = true
    @AppStorage(Settings.deleteAfterSyncKey) private var deleteAfterSync = false
    @AppStorage(Settings.ageKey) private var age = 25
    @AppStorage(Settings.weightKey) private var weight = 70
    @AppStorage(Settings.heightKey) private var height = 170
    @AppStorage(Settings.femaleKey) private var female = false
    @AppStorage(Settings.heartAlarmOnKey) private var alarmOn = false
    @AppStorage(Settings.heartAlarmMaxKey) private var alarmMax = 160
    @AppStorage(Settings.nameKey) private var name = ""
    @State private var showLog = false
    @StateObject private var avatar = AvatarStore.shared
    @State private var showCamera = false
    @State private var buzzed = false
    @State private var pushTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Screen {
                ScreenTitle(title: "Más").appear()
                bandCard.appear(0.03)

                Button { Task { await sync.sync() } } label: {
                    HStack {
                        if sync.syncing { ProgressView().tint(Theme.bg) }
                        Text(sync.syncing ? sync.status : "Sincronizar ahora").font(Theme.body(15, .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.recovery, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.bg)
                }
                .pressable()
                .disabled(sync.syncing)
                .appear(0.05)

                HStack(spacing: 8) {
                    action("Buscar pulsera", buzzed ? "checkmark" : "dot.radiowaves.left.and.right") {
                        band.send(YC.Cmd.findBand())
                        buzzed = true
                        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); buzzed = false }
                    }
                    action("Cámara remota", "camera.fill") { showCamera = true }
                }
                .disabled(band.state != .ready)
                .appear(0.07)

                section("Perfil") {
                    HStack(spacing: 14) {
                        AvatarButton(size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Foto de perfil").font(Theme.body(14, .semibold))
                            Text("Toca la imagen para cambiarla").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        if avatar.image != nil {
                            Button("Quitar", role: .destructive) { avatar.remove() }.font(Theme.body(13))
                        }
                    }
                    divider
                    HStack {
                        Text("Nombre").font(Theme.body(14))
                        TextField("Tu nombre", text: $name).multilineTextAlignment(.trailing).foregroundStyle(Theme.secondary)
                    }
                    divider
                    Stepper(value: $age, in: 10...100) { row("Edad", "\(age) años") }
                    divider
                    Stepper(value: $weight, in: 30...200) { row("Peso", "\(weight) kg") }
                    divider
                    Stepper(value: $height, in: 120...220) { row("Altura", "\(height) cm") }
                    divider
                    Picker(selection: $female) {
                        Text("Hombre").tag(false)
                        Text("Mujer").tag(true)
                    } label: { Text("Sexo").font(Theme.body(14)) }
                    .tint(Theme.secondary)
                }

                section("Metas y medición") {
                    Stepper(value: $stepGoal, in: 1000...50000, step: 500) {
                        row("Meta diaria de pasos", formatSteps(stepGoal), color: Theme.strain)
                    }
                    divider
                    Picker(selection: $heartInterval) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                    } label: { Text("Medir automáticamente cada").font(Theme.body(14)) }
                    .tint(Theme.secondary)
                }

                section("Alarma de pulso alto") {
                    Toggle(isOn: $alarmOn) { Text("Vibrar si el pulso es alto en reposo").font(Theme.body(14)) }
                        .tint(Theme.recovery)
                    if alarmOn {
                        divider
                        Stepper(value: $alarmMax, in: 100...200, step: 5) { row("Avisar sobre", "\(alarmMax) lpm", color: Theme.bad) }
                    }
                }

                section("Apple Salud") {
                    Toggle(isOn: $healthSync) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sincronizar con Apple Salud").font(Theme.body(14))
                            Text("Automático: pulso, HRV, SpO₂, sueño, pasos y entrenamientos").font(Theme.body(12)).foregroundStyle(Theme.recovery)
                        }
                    }
                    .tint(Theme.recovery)
                }

                section("Avanzado") {
                    Toggle(isOn: $deleteAfterSync) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Borrar historial de la pulsera").font(Theme.body(14))
                            Text("Después de sincronizar. Desactívalo si usas otra app con la pulsera.").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .tint(Theme.recovery)
                    divider
                    row("Firmware", band.firmware ?? "—")
                    divider
                    Button("Olvidar pulsera y buscar de nuevo", role: .destructive) { band.forgetDevice(); band.start() }
                        .font(Theme.body(14))
                }

                diagnostics
            }
            .routes()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCamera) { CameraView() }
        }
        .onChange(of: stepGoal) { _, _ in pushSettings() }
        .onChange(of: heartInterval) { _, _ in pushSettings() }
        .onChange(of: age) { _, _ in pushSettings() }
        .onChange(of: weight) { _, _ in pushSettings() }
        .onChange(of: height) { _, _ in pushSettings() }
        .onChange(of: female) { _, _ in pushSettings() }
        .onChange(of: alarmOn) { _, _ in pushSettings() }
        .onChange(of: alarmMax) { _, _ in pushSettings() }
        .onChange(of: healthSync) { _, on in
            if on { Task { _ = await HealthSync.shared.requestAuthorization() } }
        }
    }

    // MARK: Partes

    private var bandCard: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: "applewatch.side.right")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.recovery)
                    .frame(width: 56, height: 56)
                    .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(BandManager.displayName).font(Theme.display(22, .semibold)).foregroundStyle(Theme.text)
                    Text(statusLine).font(Theme.body(13))
                        .foregroundStyle(band.state == .ready ? Theme.recovery : Theme.secondary)
                }
                Spacer()
                if let b = band.battery {
                    VStack(spacing: 2) {
                        Image(systemName: band.charging ? "battery.100.bolt" : (b > 60 ? "battery.75" : b > 25 ? "battery.50" : "battery.25"))
                            .font(.system(size: 22)).foregroundStyle(b > 25 ? Theme.recovery : Theme.bad)
                        Text("\(b)%").font(Theme.display(16, .semibold))
                    }
                }
            }
        }
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { actionLabel(title, icon) }.pressable()
    }

    private func actionLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.recovery)
                .contentTransition(.symbolEffect(.replace))
            Text(title).font(Theme.body(12, .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var diagnostics: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "Diagnóstico Bluetooth")
                    Spacer()
                    Button("Copiar") { UIPasteboard.general.string = band.logText }
                        .font(Theme.body(12, .semibold)).foregroundStyle(Theme.recovery)
                    Button(showLog ? "Ocultar" : "Ver todo") { showLog.toggle() }
                        .font(Theme.body(12, .semibold)).foregroundStyle(Theme.recovery)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(showLog ? band.log : Array(band.log.suffix(8))) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.outgoing ? "→" : "←").foregroundStyle(line.outgoing ? Theme.warn : Theme.recovery)
                            Text(line.text).foregroundStyle(Color(hex: 0xC9CFD6))
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                    if band.log.isEmpty {
                        Text("Sin mensajes todavía").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private var divider: some View { Divider().overlay(Theme.divider) }

    private func pushSettings() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await sync.pushSettings()
        }
    }

    private var statusLine: String {
        guard band.state == .ready else { return band.state.label }
        if let last = sync.lastSync { return "Conectada · \(last.formatted(.relative(presentation: .named)))" }
        return "Conectada"
    }

    private func row(_ title: String, _ value: String, color: Color = Theme.secondary) -> some View {
        HStack {
            Text(title).font(Theme.body(14)).foregroundStyle(Theme.text)
            Spacer()
            Text(value).font(Theme.body(14)).foregroundStyle(color)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title).padding(.leading, 4)
            Card { VStack(alignment: .leading, spacing: 12) { content() } }
        }
    }
}

// MARK: - Cámara remota

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = CameraController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: cam.session).ignoresSafeArea()
            if cam.flash { Color.white.ignoresSafeArea().transition(.opacity) }
            VStack {
                HStack {
                    Text("Agita o toca la pulsera para tomar la foto").font(Theme.body(13, .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Button { cam.close(); dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding()
                Spacer()
                if cam.denied {
                    Text("Permite el acceso a la cámara en Ajustes.").padding().background(.ultraThinMaterial, in: Capsule())
                }
                if cam.lastSaved {
                    Label("Foto guardada en Fotos", systemImage: "checkmark.circle.fill").font(Theme.body(13, .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
                }
                Button { cam.capture() } label: {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                        .overlay(Circle().fill(.white).padding(8))
                }
                .padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
        .animation(.easeOut(duration: 0.15), value: cam.flash)
        .onAppear { cam.open() }
        .onDisappear { cam.close() }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
