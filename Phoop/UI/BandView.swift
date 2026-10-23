import SwiftUI

struct BandView: View {
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
    @AppStorage(Settings.sleepNeedKey) private var sleepNeed = 8.0
    @State private var showLog = false

    var body: some View {
        NavigationStack {
            Screen {
                ScreenTitle(title: "Pulsera")

                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.recovery)
                            .frame(width: 52, height: 52)
                            .background(Color(hex: 0x1C2026), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(band.deviceName).font(Theme.body(16, .semibold)).foregroundStyle(Theme.text)
                            Text(statusLine).font(Theme.body(13))
                                .foregroundStyle(band.state == .ready ? Theme.recovery : Theme.secondary)
                        }
                        Spacer()
                        if let b = band.battery {
                            Label("\(b)%", systemImage: band.charging ? "battery.100.bolt" : "battery.75")
                                .font(Theme.display(18, .semibold)).foregroundStyle(Theme.text)
                        }
                    }
                }

                Button {
                    Task { await sync.sync() }
                } label: {
                    HStack {
                        if sync.syncing { ProgressView().tint(Theme.bg) }
                        Text(sync.syncing ? sync.status : "Sincronizar ahora").font(Theme.body(15, .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.recovery, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.bg)
                }
                .disabled(sync.syncing)

                section("Metas y medición") {
                    Stepper(value: $stepGoal, in: 1000...50000, step: 500) {
                        row("Meta diaria de pasos", formatSteps(stepGoal), color: Theme.strain)
                    }
                    Divider().overlay(Theme.divider)
                    Picker(selection: $heartInterval) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                    } label: { Text("Medir pulso cada").font(Theme.body(14)).foregroundStyle(Theme.text) }
                    .tint(Theme.secondary)
                    Divider().overlay(Theme.divider)
                    Stepper(value: $sleepNeed, in: 5...11, step: 0.5) {
                        row("Sueño que necesitas", String(format: "%.1f h", sleepNeed))
                    }
                }

                section("Apple Salud") {
                    Toggle(isOn: $healthSync) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sincronizar con Apple Salud").font(Theme.body(14)).foregroundStyle(Theme.text)
                            Text("Automático · cada sincronización").font(Theme.body(12)).foregroundStyle(Theme.recovery)
                        }
                    }
                    .tint(Theme.recovery)
                }

                section("Tus datos (para calcular esfuerzo)") {
                    Stepper(value: $age, in: 10...100) { row("Edad", "\(age) años") }
                    Divider().overlay(Theme.divider)
                    Stepper(value: $weight, in: 30...200) { row("Peso", "\(weight) kg") }
                    Divider().overlay(Theme.divider)
                    Stepper(value: $height, in: 120...220) { row("Altura", "\(height) cm") }
                    Divider().overlay(Theme.divider)
                    Picker(selection: $female) {
                        Text("Hombre").tag(false)
                        Text("Mujer").tag(true)
                    } label: { Text("Sexo").font(Theme.body(14)).foregroundStyle(Theme.text) }
                    .tint(Theme.secondary)
                }

                section("Avanzado") {
                    Toggle(isOn: $deleteAfterSync) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Borrar historial de la pulsera").font(Theme.body(14)).foregroundStyle(Theme.text)
                            Text("Después de sincronizar. Desactívalo si usas HealthWear.").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .tint(Theme.recovery)
                    Divider().overlay(Theme.divider)
                    row("Firmware", band.firmware ?? "—")
                    Divider().overlay(Theme.divider)
                    Button("Olvidar pulsera y buscar de nuevo", role: .destructive) { band.forgetDevice(); band.start() }
                        .font(Theme.body(14))
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Diagnóstico Bluetooth").font(Theme.body(12)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.secondary)
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
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: stepGoal) { _, _ in pushSettings() }
        .onChange(of: heartInterval) { _, _ in pushSettings() }
        .onChange(of: age) { _, _ in pushSettings() }
        .onChange(of: weight) { _, _ in pushSettings() }
        .onChange(of: height) { _, _ in pushSettings() }
        .onChange(of: female) { _, _ in pushSettings() }
        .onChange(of: healthSync) { _, on in
            if on { Task { _ = await HealthSync.shared.requestAuthorization() } }
        }
    }

    @State private var pushTask: Task<Void, Never>?
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
        if let last = sync.lastSync {
            return "Conectada · sincronizado \(last.formatted(.relative(presentation: .named)))"
        }
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
            Text(title).font(Theme.body(12)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.secondary)
                .padding(.leading, 4)
            Card { VStack(alignment: .leading, spacing: 12) { content() } }
        }
    }
}
