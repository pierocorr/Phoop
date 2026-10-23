import SwiftUI

struct TodayView: View {
    @Binding var tab: Int
    @EnvironmentObject private var band: BandManager
    @EnvironmentObject private var sync: SyncEngine
    @EnvironmentObject private var metrics: MetricsStore
    @AppStorage(Settings.stepGoalKey) private var stepGoal = 11000

    private var d: DayMetrics { metrics.day }
    private var steps: Int { max(d.steps, band.liveSport?.steps ?? 0) }

    var body: some View {
        Screen {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased())
                        .font(Theme.body(13, .medium)).foregroundStyle(Theme.secondary).tracking(1)
                    Text("Hoy").font(Theme.display(32)).textCase(.uppercase).foregroundStyle(Theme.text)
                }
                Spacer()
                Button { tab = 4 } label: {
                    HStack(spacing: 8) {
                        Circle().fill(band.state == .ready ? Theme.recovery : Theme.secondary).frame(width: 8, height: 8)
                        Text(band.state == .ready ? "\(band.deviceName) · \(band.battery.map { "\($0)%" } ?? "—")" : band.state.label)
                            .font(Theme.body(13)).foregroundStyle(Color(hex: 0xC9CFD6))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                }
            }

            HStack(spacing: 8) {
                ringButton(progress: d.sleepPerformance ?? 0, color: Theme.sleep,
                           label: d.sleepPerformance.map { "\(Int($0 * 100))%" } ?? "—", title: "Sueño", to: 1)
                ringButton(progress: Double(d.recovery ?? 0) / 100, color: Theme.recoveryColor(d.recovery),
                           label: d.recovery.map { "\($0)%" } ?? "—", title: "Recuperación", to: 2)
                ringButton(progress: d.strain / 21, color: Theme.strain,
                           label: String(format: "%.1f", d.strain), title: "Esfuerzo", to: 3)
            }

            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recomendación").font(Theme.body(12, .semibold)).textCase(.uppercase)
                        .foregroundStyle(Theme.recovery).tracking(0.8)
                    Text(d.recommendation).font(Theme.body(15)).foregroundStyle(Color(hex: 0xDDE2E8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                StatTile(title: "Pulso ahora", value: band.liveHR.map(String.init) ?? "—", unit: "lpm")
                StatTile(title: "HRV", value: d.hrv.map(String.init) ?? "—", unit: "ms")
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pasos · meta \(formatSteps(stepGoal))").font(Theme.body(12)).foregroundStyle(Theme.secondary)
                        Text(formatSteps(steps)).font(Theme.display(26, .semibold)).foregroundStyle(Theme.text)
                        ProgressBar(value: Double(steps) / Double(max(1, stepGoal)), color: Theme.strain)
                    }
                }
                StatTile(title: "SpO₂", value: d.spo2.map(String.init) ?? "—", unit: "%")
            }

            if !sync.status.isEmpty {
                Text(sync.syncing ? sync.status : "\(sync.status) · \(sync.lastSync?.formatted(date: .omitted, time: .shortened) ?? "")")
                    .font(Theme.body(12)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .refreshable { await sync.sync() }
    }

    private func ringButton(progress: Double, color: Color, label: String, title: String, to: Int) -> some View {
        Button { tab = to } label: {
            VStack(spacing: 8) {
                Ring(progress: progress, color: color, label: label)
                Text(title).font(Theme.body(11, .semibold)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ProgressBar: View {
    var value: Double
    var color: Color
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: height)
    }
}
