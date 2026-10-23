import SwiftUI

struct SleepView: View {
    @EnvironmentObject private var metrics: MetricsStore
    private var d: DayMetrics { metrics.day }

    var body: some View {
        Screen {
            ScreenTitle(title: "Sueño", trailing: d.sleep.map {
                "Anoche · \($0.start.formatted(date: .omitted, time: .shortened)) – \($0.end.formatted(date: .omitted, time: .shortened))"
            })

            if let s = d.sleep {
                Card(padding: 18) {
                    HStack(spacing: 18) {
                        Ring(progress: d.sleepPerformance ?? 0, color: Theme.sleep,
                             label: "\(Int((d.sleepPerformance ?? 0) * 100))%", size: 104)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDuration(s.asleepSeconds)).font(Theme.display(30)).foregroundStyle(Theme.text)
                            Text("de \(formatDuration(d.sleepNeedSeconds)) que necesitas").font(Theme.body(13)).foregroundStyle(Theme.secondary)
                            if d.sleepDebtSeconds > 0 {
                                Text("Deuda de sueño: \(formatDuration(d.sleepDebtSeconds))").font(Theme.body(13)).foregroundStyle(Theme.rem)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fases").font(Theme.body(12)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.secondary)
                        Hypnogram(session: s)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    StatTile(title: "Profundo", value: formatDuration(s.seconds(.deep)))
                    StatTile(title: "REM", value: formatDuration(s.seconds(.rem)))
                    StatTile(title: "Ligero", value: formatDuration(s.seconds(.light)))
                    StatTile(title: "Despierto", value: "\(formatDuration(s.seconds(.awake))) · \(s.wakeCount)×")
                }
            } else {
                Card {
                    Text("Todavía no hay una noche registrada. Duerme con la pulsera puesta y abre Phoop al despertar para sincronizar.")
                        .font(Theme.body(15)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

/// Gráfico de fases: una fila por fase, con los tramos en su posición horaria.
struct Hypnogram: View {
    let session: SleepSession

    private let rows: [(SleepStageType, Color)] = [(.awake, Theme.awake), (.rem, Theme.rem), (.light, Theme.light), (.deep, Theme.deep)]

    var body: some View {
        let total = max(1, session.end.timeIntervalSince(session.start))
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { stage, color in
                HStack(spacing: 8) {
                    Text(stage.label).font(Theme.body(11)).foregroundStyle(Theme.secondary).frame(width: 62, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x1C2026))
                            ForEach(session.stages.filter { $0.type == stage.rawValue }, id: \.self) { st in
                                let x = st.start.timeIntervalSince(session.start) / total
                                let w = Double(st.seconds) / total
                                RoundedRectangle(cornerRadius: 4).fill(color)
                                    .frame(width: max(2, g.size.width * w))
                                    .offset(x: g.size.width * max(0, x))
                            }
                        }
                    }
                    .frame(height: 14)
                }
            }
            HStack {
                Text(session.start.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(session.end.formatted(date: .omitted, time: .shortened))
            }
            .font(Theme.body(11)).foregroundStyle(Theme.secondary).padding(.leading, 70)
        }
    }
}
