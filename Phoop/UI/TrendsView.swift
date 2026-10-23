import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var store: DayStore
    @State private var range = 7

    private let items: [(MetricsEngine.TrendMetric, Color)] = [
        (.recovery, Theme.recovery), (.strain, Theme.strain), (.sleep, Theme.sleep), (.hrv, Theme.health),
        (.rhr, Theme.bad), (.steps, Theme.strain), (.spo2, Theme.health), (.stress, Theme.warn)
    ]

    var body: some View {
        NavigationStack {
            Screen {
                ScreenTitle(title: "Tendencias").appear()
                Picker("Rango", selection: $range) {
                    Text("Semana").tag(7)
                    Text("Mes").tag(30)
                }
                .pickerStyle(.segmented)
                .appear(0.03)

                summary.appear(0.06)

                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    NavigationLink(value: Route.metric(item.0)) {
                        trendCard(item.0, color: item.1)
                    }
                    .pressable()
                    .appear(0.08 + Double(idx) * 0.03)
                }
            }
            .animation(.easeInOut, value: range)
            .routes()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var summary: some View {
        let rec = store.trend(.recovery, days: range).map(\.value)
        let sl = store.trend(.sleep, days: range).map(\.value)
        let st = store.trend(.strain, days: range).map(\.value)
        func avg(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        return HStack(spacing: 8) {
            mini("Recuperación", avg(rec).map { "\(Int($0))%" } ?? "—", Theme.recovery)
            mini("Sueño", avg(sl).map { String(format: "%.1f h", $0) } ?? "—", Theme.sleep)
            mini("Esfuerzo", avg(st).map { String(format: "%.1f", $0) } ?? "—", Theme.strain)
        }
    }

    private func mini(_ title: String, _ value: String, _ color: Color) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prom. \(title.lowercased())").font(Theme.body(11)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Text(value).font(Theme.display(24, .semibold)).foregroundStyle(color)
            }
        }
    }

    private func trendCard(_ m: MetricsEngine.TrendMetric, color: Color) -> some View {
        let pts = store.trend(m, days: range)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(m.title).font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    if let last = pts.last {
                        Text(fmt(last.value, m) + (m.unit.isEmpty ? "" : " \(m.unit)"))
                            .font(Theme.display(20, .semibold)).foregroundStyle(color)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                TrendChart(points: pts, color: color, height: 90, showAverage: false)
            }
        }
    }

    private func fmt(_ v: Double, _ m: MetricsEngine.TrendMetric) -> String {
        switch m {
        case .strain, .sleep: return String(format: "%.1f", v)
        case .steps: return formatSteps(Int(v))
        default: return String(format: "%.0f", v)
        }
    }
}
