import SwiftUI
import SwiftData
import Charts

struct HealthView: View {
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var band: BandManager
    @StateObject private var measure = MeasureManager.shared
    @State private var showECG = false

    private var d: DayMetrics { store.today }

    var body: some View {
        NavigationStack {
            Screen {
                ScreenTitle(title: "Salud").appear()

                // Medir ahora
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionLabel(text: "Medir ahora")
                            Spacer()
                            if measure.running != nil {
                                Button("Detener") { measure.stop() }.font(Theme.body(13, .semibold)).foregroundStyle(Theme.bad)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(YC.MeasureType.allCases) { t in
                                Button { measure.start(t) } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: t.icon).font(.system(size: 20, weight: .semibold))
                                            .symbolEffect(.pulse, options: .repeating, isActive: measure.running == t)
                                        Text(t.label).font(Theme.body(10, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                    }
                                    .foregroundStyle(measure.running == t ? Theme.bg : Theme.text)
                                    .frame(maxWidth: .infinity, minHeight: 66)
                                    .background(measure.running == t ? Theme.health : Theme.cardHi, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .pressable()
                                .disabled(measure.running != nil && measure.running != t)
                            }
                        }
                        if let msg = measure.message {
                            HStack {
                                if measure.running != nil { ProgressView().tint(Theme.health) }
                                Text(msg).font(Theme.body(13)).foregroundStyle(Theme.secondary)
                                Spacer()
                                if let v = measure.liveValue {
                                    Text(v).font(Theme.display(22, .semibold)).foregroundStyle(Theme.health).contentTransition(.numericText())
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut, value: measure.message)
                }
                .appear(0.03)

                // Estrés y energía
                NavigationLink(value: Route.metric(.stress)) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionLabel(text: "Estrés")
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                            }
                            HStack(spacing: 18) {
                                Ring(progress: (d.stress ?? 0) / 100, color: Theme.stressColor(d.stress), lineWidth: 9,
                                     label: d.stress.map { String(format: "%.0f", $0) } ?? "—", sublabel: d.stress.map { DayMetrics.stressLabel($0) }, size: 96)
                                VStack(alignment: .leading, spacing: 8) {
                                    stat("Energía corporal", d.energy.map { String(format: "%.0f", $0) } ?? "—", Theme.recovery)
                                    stat("VO₂ máx. estimado", d.vo2max.map { "\($0)" } ?? "—", Theme.health)
                                }
                            }
                            if d.stressSeries.count > 1 {
                                Chart(Array(d.stressSeries.enumerated()), id: \.offset) { _, p in
                                    LineMark(x: .value("Hora", p.0), y: .value("Estrés", p.1))
                                        .foregroundStyle(Theme.warn).interpolationMethod(.catmullRom)
                                }
                                .chartYScale(domain: 0...100)
                                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Theme.secondary) } }
                                .frame(height: 90)
                            } else {
                                Text("Usa “Medir ahora → Estrés” o espera a las mediciones automáticas.")
                                    .font(Theme.body(12)).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
                .pressable()
                .appear(0.06)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    NavigationLink(value: Route.metric(.spo2)) {
                        StatTile(title: "Oxígeno (SpO₂)", value: d.shownSpO2.map(String.init) ?? "—", unit: "%", color: Theme.health)
                    }
                    NavigationLink(value: Route.metric(.hrv)) {
                        StatTile(title: "HRV", value: d.shownHRV.map(String.init) ?? "—", unit: "ms", color: Theme.health)
                    }
                    StatTile(title: "Respiración", value: d.shownResp.map(String.init) ?? "—", unit: "rpm")
                    StatTile(title: "Temperatura", value: d.shownTemp.map { String(format: "%.1f", $0) } ?? "—", unit: "°C")
                }
                .pressable()
                .appear(0.09)

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionLabel(text: "Presión arterial")
                            Spacer()
                            Text("ESTIMADA").font(Theme.body(10, .bold)).foregroundStyle(Theme.warn)
                                .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.warn.opacity(0.15), in: Capsule())
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(d.latestBP.map { "\($0.0)/\($0.1)" } ?? "—").font(Theme.display(34)).foregroundStyle(Theme.text)
                            Text("mmHg").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                        }
                        Text("La pulsera la calcula a partir del pulso; no reemplaza a un tensiómetro.")
                            .font(Theme.body(12)).foregroundStyle(Theme.secondary)
                    }
                }
                .appear(0.12)

                // ECG
                Button { showECG = true } label: {
                    Card {
                        HStack(spacing: 14) {
                            Image(systemName: "waveform.path.ecg.rectangle").font(.system(size: 26)).foregroundStyle(Theme.bad)
                                .frame(width: 48, height: 48).background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Electrocardiograma").font(Theme.display(22, .semibold)).foregroundStyle(Theme.text)
                                Text("Prueba de 30 s · beta").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .pressable()
                .disabled(band.state != .ready)
                .appear(0.15)

                NavigationLink(value: Route.ecgHistory) {
                    Text("Ver ECG guardados").font(Theme.body(14, .semibold)).foregroundStyle(Theme.health)
                        .frame(maxWidth: .infinity)
                }
            }
            .routes()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showECG) { ECGView() }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.body(12)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.display(24, .semibold)).foregroundStyle(color)
        }
    }
}

// MARK: - ECG

struct ECGView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ecg = ECGManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(ecg.recording ? "Mantén el dedo sobre el electrodo de la pulsera y no te muevas"
                                   : "Siéntate, apoya el brazo y toca el electrodo de la pulsera con un dedo de la otra mano.")
                    .font(Theme.body(15)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)

                ECGWave(samples: ecg.display)
                    .frame(height: 220)
                    .background(
                        Canvas { ctx, size in
                            var p = Path()
                            stride(from: 0, through: size.width, by: 20).forEach { x in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) }
                            stride(from: 0, through: size.height, by: 20).forEach { y in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) }
                            ctx.stroke(p, with: .color(Theme.bad.opacity(0.12)), lineWidth: 0.5)
                        }
                    )
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))

                HStack {
                    LiveHeart(bpm: ecg.bpm)
                    Spacer()
                    Text("\(Int(ecg.progress * ECGManager.duration)) / \(Int(ECGManager.duration)) s")
                        .font(Theme.display(20, .semibold)).monospacedDigit()
                }
                ProgressBar(value: ecg.progress, color: Theme.bad, height: 8)

                if let r = ecg.lastResult {
                    Text(r).font(Theme.body(14)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    if ecg.recording { ecg.stop(context: context) } else { ecg.start() }
                } label: {
                    Text(ecg.recording ? "Detener" : "Iniciar ECG").font(Theme.body(16, .bold)).foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity, minHeight: 52).background(ecg.recording ? Theme.secondary : Theme.bad, in: Capsule())
                }
                Text("Función en prueba. No es un dispositivo médico ni sirve para diagnosticar.")
                    .font(Theme.body(11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("ECG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        if ecg.recording { ecg.stop(context: context) }
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Dibuja la onda del ECG escalada a su alto.
struct ECGWave: View {
    var samples: [Int]
    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 2 else { return }
            let lo = Double(samples.min() ?? 0), hi = Double(samples.max() ?? 1)
            let span = max(1, hi - lo)
            var p = Path()
            for (i, s) in samples.enumerated() {
                let x = size.width * Double(i) / Double(samples.count - 1)
                let y = size.height * (1 - (Double(s) - lo) / span) * 0.9 + size.height * 0.05
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(p, with: .color(Theme.bad), lineWidth: 1.6)
        }
    }
}

struct ECGHistoryView: View {
    @Query(sort: \ECGRecord.time, order: .reverse) private var records: [ECGRecord]
    var body: some View {
        Screen {
            if records.isEmpty {
                Text("Todavía no hay ECG guardados.").font(Theme.body(15)).foregroundStyle(Theme.secondary)
            }
            ForEach(records) { r in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(r.time.formatted(date: .abbreviated, time: .shortened)).font(Theme.body(14, .semibold))
                            Spacer()
                            Text(r.bpm > 0 ? "\(r.bpm) lpm" : "").font(Theme.display(18, .semibold)).foregroundStyle(Theme.bad)
                        }
                        ECGWave(samples: Array(r.samples.prefix(1500))).frame(height: 110)
                    }
                }
            }
        }
        .navigationTitle("ECG guardados")
        .navigationBarTitleDisplayMode(.inline)
    }
}
