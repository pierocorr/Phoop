import SwiftUI
import UIKit
import Charts

enum Theme {
    static let bg = Color(hex: 0x0B0D10)
    static let card = Color(hex: 0x15181D)
    static let cardHi = Color(hex: 0x1C2026)
    static let track = Color(hex: 0x252A31)
    static let divider = Color(hex: 0x1F242B)
    static let tabBar = Color(hex: 0x111418)
    static let text = Color(hex: 0xF2F4F7)
    static let secondary = Color(hex: 0x9AA3AF)

    static let recovery = Color(hex: 0x38E0B0)
    static let strain = Color(hex: 0xFF8A3D)
    static let sleep = Color(hex: 0x8F8CFF)
    static let health = Color(hex: 0x5AC8FA)
    static let warn = Color(hex: 0xFFB27A)
    static let bad = Color(hex: 0xFF6B6B)

    static let deep = Color(hex: 0x4F4ACF)
    static let light = Color(hex: 0x8F8CFF)
    static let rem = Color(hex: 0xC4C2FF)
    static let awake = Color(hex: 0xE8E9EE)

    static let zoneColors: [Color] = [Color(hex: 0xFFD2AE), Color(hex: 0xFFB27A), Color(hex: 0xFF9A4D), Color(hex: 0xFF7A45), Color(hex: 0xFF5A5A)]
    static let zoneNames = ["Z1 · ligero", "Z2 · suave", "Z3 · medio", "Z4 · duro", "Z5 · máx"]

    static func recoveryColor(_ v: Int?) -> Color {
        guard let v else { return secondary }
        return v >= 67 ? recovery : (v >= 34 ? Color(hex: 0xFFD45A) : bad)
    }

    static func stressColor(_ v: Double?) -> Color {
        guard let v else { return secondary }
        return v < 30 ? recovery : v < 60 ? health : v < 80 ? warn : bad
    }

    /// Tipografía condensada (Saira Condensed si está incluida; si no, la condensada del sistema).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "SairaCondensed-Bold"
        case .semibold: name = "SairaCondensed-SemiBold"
        default: name = "SairaCondensed-Medium"
        }
        if UIFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: weight).width(.condensed)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Animaciones

/// Aparición suave con retraso (para escalonar tarjetas).
struct AppearModifier: ViewModifier {
    var delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func appear(_ delay: Double = 0) -> some View { modifier(AppearModifier(delay: delay)) }

    /// Toque con rebote para tarjetas pulsables.
    func pressable() -> some View { buttonStyle(PressStyle()) }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Componentes

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Anillo que se llena con animación al aparecer y al cambiar de valor.
struct Ring: View {
    var progress: Double          // 0…1
    var color: Color
    var lineWidth: CGFloat = 10
    var label: String
    var sublabel: String? = nil
    var size: CGFloat = 92
    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(1, animated)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label)
                    .font(Theme.display(size * 0.3))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                if let sublabel {
                    Text(sublabel).font(Theme.body(size * 0.065, .semibold)).foregroundStyle(Theme.secondary)
                        .textCase(.uppercase)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            animated = 0
            withAnimation(.easeOut(duration: 1.1).delay(0.1)) { animated = progress }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.easeInOut(duration: 0.8)) { animated = new }
        }
    }
}

struct ScreenTitle: View {
    var title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(Theme.display(32)).textCase(.uppercase).foregroundStyle(Theme.text)
            Spacer()
            if let trailing { Text(trailing).font(Theme.body(13)).foregroundStyle(Theme.secondary) }
        }
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text).font(Theme.body(12, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(Theme.secondary)
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var unit: String? = nil
    var color: Color = Theme.text
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(Theme.display(26, .semibold)).foregroundStyle(color)
                        .contentTransition(.numericText())
                    if let unit { Text(unit).font(Theme.body(13)).foregroundStyle(Theme.secondary) }
                }
            }
        }
    }
}

struct MetricRow: View {
    var icon: String? = nil
    var title: String
    var subtitle: String
    var value: String
    var delta: String? = nil
    var deltaGood: Bool = true
    var chevron: Bool = false
    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.secondary)
                        .frame(width: 34, height: 34).background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.body(14, .semibold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value).font(Theme.display(22, .semibold)).foregroundStyle(Theme.text)
                    if let delta {
                        Text(delta).font(Theme.body(12)).foregroundStyle(deltaGood ? Theme.recovery : Theme.warn)
                    }
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

struct ProgressBar: View {
    var value: Double
    var color: Color
    var height: CGFloat = 6
    @State private var animated: Double = 0
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: g.size.width * max(0, min(1, animated)))
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { animated = value } }
        .onChange(of: value) { _, v in withAnimation(.easeInOut(duration: 0.6)) { animated = v } }
    }
}

/// Gráfico de barras por día para tendencias.
struct TrendChart: View {
    var points: [MetricsEngine.TrendPoint]
    var color: Color
    var height: CGFloat = 140
    var showAverage = true

    var body: some View {
        if points.isEmpty {
            Text("Todavía no hay datos suficientes.")
                .font(Theme.body(13)).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: height * 0.5)
        } else {
            let avg = points.map(\.value).reduce(0, +) / Double(points.count)
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Día", p.day, unit: .day), y: .value("Valor", p.value))
                        .foregroundStyle(color.gradient)
                        .cornerRadius(4)
                }
                if showAverage {
                    RuleMark(y: .value("Promedio", avg))
                        .foregroundStyle(Theme.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: points.count > 10 ? 7 : 1)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(Theme.secondary)
            } }
            .chartYAxis { AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Theme.divider)
                AxisValueLabel().foregroundStyle(Theme.secondary)
            } }
            .frame(height: height)
        }
    }
}

/// Corazón que late (pulso en vivo).
struct LiveHeart: View {
    var bpm: Int?
    var color: Color = Theme.bad
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(color)
                .symbolEffect(.pulse, options: .repeating, isActive: bpm != nil)
            Text(bpm.map { "\($0)" } ?? "—").font(Theme.display(20, .semibold)).foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text("lpm").font(Theme.body(12)).foregroundStyle(Theme.secondary)
        }
    }
}

func formatDuration(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60
    return h > 0 ? "\(h) h \(m) min" : "\(m) min"
}

func formatClock(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                     : String(format: "%02d:%02d", s / 60, s % 60)
}

func formatSteps(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
