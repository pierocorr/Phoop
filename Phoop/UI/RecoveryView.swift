import SwiftUI

struct RecoveryView: View {
    @EnvironmentObject private var metrics: MetricsStore
    private var d: DayMetrics { metrics.day }

    var body: some View {
        Screen {
            ScreenTitle(title: "Recuperación")

            VStack(spacing: 8) {
                Ring(progress: Double(d.recovery ?? 0) / 100, color: Theme.recoveryColor(d.recovery), lineWidth: 12,
                     label: d.recovery.map { "\($0)%" } ?? "—", sublabel: bandLabel, size: 200)
                Text(d.recovery == nil
                     ? "Aún no hay datos de sueño. Duerme con la pulsera y sincroniza al despertar."
                     : "Calculado con tu HRV, pulso en reposo y sueño de anoche.")
                    .font(Theme.body(14)).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 290)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            MetricRow(title: "HRV", subtitle: "Variabilidad cardíaca",
                      value: d.hrv.map { "\($0) ms" } ?? "—",
                      delta: delta(d.hrv, d.hrvBaseline, unit: ""), deltaGood: (d.hrv ?? 0) >= (d.hrvBaseline ?? 0))
            MetricRow(title: "Pulso en reposo", subtitle: "Mínimo estable al dormir",
                      value: d.restingHR.map { "\($0) lpm" } ?? "—",
                      delta: delta(d.restingHR, d.restingHRBaseline, unit: ""), deltaGood: (d.restingHR ?? 0) <= (d.restingHRBaseline ?? 999))
            MetricRow(title: "Oxígeno (SpO₂)", subtitle: "Promedio nocturno", value: d.spo2.map { "\($0)%" } ?? "—")
            MetricRow(title: "Temperatura", subtitle: "Muñeca", value: d.tempC.map { String(format: "%.1f °C", $0) } ?? "—")
            if let r = d.respiration {
                MetricRow(title: "Respiración", subtitle: "Por minuto, noche", value: "\(r) rpm")
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Últimos 7 días").font(Theme.body(12)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.secondary)
                    HStack(alignment: .bottom) {
                        ForEach(Array(metrics.week.enumerated()), id: \.offset) { _, item in
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(item.1 == nil ? Theme.track : Theme.recoveryColor(item.1))
                                    .frame(width: 30, height: max(6, CGFloat(item.1 ?? 8) * 0.64))
                                Text(item.0.formatted(.dateTime.weekday(.narrow)).uppercased())
                                    .font(Theme.body(11)).foregroundStyle(Theme.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 84, alignment: .bottom)
                }
            }
        }
    }

    private var bandLabel: String? {
        switch d.recoveryBand {
        case .high: return "Alta"
        case .medium: return "Moderada"
        case .low: return "Baja"
        case .none: return nil
        }
    }

    private func delta(_ v: Int?, _ base: Int?, unit: String) -> String? {
        guard let v, let base, v != base else { return nil }
        let diff = v - base
        return "\(diff > 0 ? "▲" : "▼") \(abs(diff)) vs promedio"
    }
}
