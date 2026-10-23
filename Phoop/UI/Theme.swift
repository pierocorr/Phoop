import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(hex: 0x0B0D10)
    static let card = Color(hex: 0x15181D)
    static let track = Color(hex: 0x252A31)
    static let divider = Color(hex: 0x1F242B)
    static let tabBar = Color(hex: 0x111418)
    static let text = Color(hex: 0xF2F4F7)
    static let secondary = Color(hex: 0x9AA3AF)

    static let recovery = Color(hex: 0x38E0B0)
    static let strain = Color(hex: 0xFF8A3D)
    static let sleep = Color(hex: 0x8F8CFF)
    static let warn = Color(hex: 0xFFB27A)
    static let bad = Color(hex: 0xFF6B6B)

    static let deep = Color(hex: 0x4F4ACF)
    static let light = Color(hex: 0x8F8CFF)
    static let rem = Color(hex: 0xC4C2FF)
    static let awake = Color(hex: 0xE8E9EE)

    static func recoveryColor(_ v: Int?) -> Color {
        guard let v else { return secondary }
        return v >= 67 ? recovery : (v >= 34 ? warn : bad)
    }

    /// Tipografía condensada (Saira Condensed, si está incluida; si no, la condensada del sistema).
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

struct Ring: View {
    var progress: Double          // 0…1
    var color: Color
    var lineWidth: CGFloat = 10
    var label: String
    var sublabel: String? = nil
    var size: CGFloat = 92

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: progress)
            VStack(spacing: 0) {
                Text(label).font(Theme.display(size * 0.3)).foregroundStyle(Theme.text)
                if let sublabel {
                    Text(sublabel).font(Theme.body(size * 0.07, .semibold)).foregroundStyle(Theme.secondary)
                        .textCase(.uppercase)
                }
            }
        }
        .frame(width: size, height: size)
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

struct StatTile: View {
    var title: String
    var value: String
    var unit: String? = nil
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(Theme.display(26, .semibold)).foregroundStyle(Theme.text)
                    if let unit { Text(unit).font(Theme.body(13)).foregroundStyle(Theme.secondary) }
                }
            }
        }
    }
}

struct MetricRow: View {
    var title: String
    var subtitle: String
    var value: String
    var delta: String? = nil
    var deltaGood: Bool = true
    var body: some View {
        Card(padding: 14) {
            HStack {
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
            }
        }
    }
}

func formatDuration(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60
    return h > 0 ? "\(h) h \(m) min" : "\(m) min"
}

func formatSteps(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
