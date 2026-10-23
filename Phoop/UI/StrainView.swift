import SwiftUI
import Charts

struct StrainView: View {
    @EnvironmentObject private var metrics: MetricsStore
    @EnvironmentObject private var band: BandManager
    private var d: DayMetrics { metrics.day }

    private let zones: [(String, Color)] = [
        ("Z1 · ligero", Color(hex: 0xFFD2AE)), ("Z2 · suave", Color(hex: 0xFFB27A)),
        ("Z3 · medio", Color(hex: 0xFF9A4D)), ("Z4 · duro", Color(hex: 0xFF7A45)), ("Z5 · máx", Color(hex: 0xFF5A5A))
    ]

    var body: some View {
        Screen {
            ScreenTitle(title: "Esfuerzo")

            Card(padding: 18) {
                HStack(spacing: 18) {
                    Ring(progress: d.strain / 21, color: Theme.strain, label: String(format: "%.1f", d.strain), size: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Escala 0 – 21").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                        Text(DayMetrics.strainLabel(d.strain)).font(Theme.display(22)).textCase(.uppercase).foregroundStyle(Theme.text)
                        Text("Objetivo de hoy: \(Int(d.strainTarget.lowerBound)) – \(Int(d.strainTarget.upperBound))")
                            .font(Theme.body(13)).foregroundStyle(Theme.warn)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Pulso de hoy").font(Theme.body(12)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(band.liveHR.map { "\($0) lpm" } ?? "—").font(Theme.display(22, .semibold)).foregroundStyle(Theme.strain)
                    }
                    if d.hrToday.count > 1 {
                        Chart(Array(d.hrToday.enumerated()), id: \.offset) { _, p in
                            LineMark(x: .value("Hora", p.0), y: .value("lpm", p.1))
                                .foregroundStyle(Theme.strain)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
                        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisValueLabel() } }
                        .frame(height: 110)
                    } else {
                        Text("El gráfico aparecerá cuando haya más mediciones de hoy.")
                            .font(Theme.body(13)).foregroundStyle(Theme.secondary)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tiempo en zonas").font(Theme.body(12)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.secondary)
                    let maxMin = max(1, d.zoneMinutes.max() ?? 1)
                    ForEach((0..<5).reversed(), id: \.self) { i in
                        HStack(spacing: 10) {
                            Text(zones[i].0).font(Theme.body(12)).foregroundStyle(Color(hex: 0xC9CFD6)).frame(width: 74, alignment: .leading)
                            ProgressBar(value: Double(d.zoneMinutes[i]) / Double(maxMin), color: zones[i].1, height: 10)
                            Text(formatDuration(d.zoneMinutes[i] * 60)).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                }
            }

            let sport = band.liveSport
            HStack(spacing: 8) {
                StatTile(title: "Pasos", value: formatSteps(max(d.steps, sport?.steps ?? 0)))
                StatTile(title: "Distancia", value: String(format: "%.2f", Double(max(d.distanceM, sport?.distanceM ?? 0)) / 1000), unit: "km")
                StatTile(title: "Calorías", value: "\(max(d.kcal, sport?.kcal ?? 0))", unit: "kcal")
            }
        }
    }
}
