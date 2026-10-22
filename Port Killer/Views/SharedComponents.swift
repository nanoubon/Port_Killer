import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SectionHeading: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
                Text(trailing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.pkMuted.opacity(0.72))
            }
            Spacer()
        }
    }
}

struct CardShell<Content: View>: View {
    let fill: Color
    let radius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(fill: Color, radius: CGFloat, padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.fill = fill
        self.radius = radius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.pkStroke.opacity(0.55), lineWidth: 1)
                    )
            )
    }
}

struct PortThumbnailView: View {
    let port: PortItem
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let icon = port.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.6, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(Color.pkPrimary)
        .background(
            RoundedRectangle(cornerRadius: max(6, size * 0.25), style: .continuous)
                .fill(Color.pkSurface)
        )
    }

    private var fallbackSymbol: String {
        switch port.processName.lowercased() {
        case let name where name.contains("postgre"): return "cylinder.split.1x2"
        case let name where name.contains("redis"): return "cube.box.fill"
        case let name where name.contains("python"): return "chevron.left.forwardslash.chevron.right"
        case let name where name.contains("nginx"): return "network"
        default: return "terminal.fill"
        }
    }
}

struct StatusPill: View {
    let state: PortState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(state.displayTitle)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(accent)
        .background(
            Capsule(style: .continuous)
                .fill(accent.opacity(0.12))
        )
    }

    private var accent: Color {
        switch state {
        case .listening: return Color.pkSecondary
        case .busy: return Color.pkWarning
        case .idle: return Color.pkMuted
        case .dormant: return Color.pkStroke
        }
    }
}

struct SecondaryActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryActionButtonStyle())
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 12)
            .foregroundStyle(Color.pkText)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pkElevated.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pkStroke.opacity(0.5), lineWidth: 1)
            )
    }
}

struct TertiaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 12)
            .foregroundStyle(Color.pkMuted)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pkSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pkStroke.opacity(0.45), lineWidth: 1)
            )
    }
}

struct DangerActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .padding(.vertical, 12)
            .foregroundStyle(Color.pkDangerText)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pkDanger.opacity(configuration.isPressed ? 0.22 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pkDanger.opacity(0.7), lineWidth: 1)
            )
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .padding(.vertical, 12)
            .foregroundStyle(Color.pkOnPrimary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pkPrimary.opacity(configuration.isPressed ? 0.84 : 1))
            )
    }
}

struct QuitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .padding(.vertical, 10)
            .foregroundStyle(Color.pkDangerText.opacity(configuration.isPressed ? 0.7 : 1))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.pkDanger.opacity(configuration.isPressed ? 0.5 : 0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.pkDanger.opacity(0.5), lineWidth: 1)
                    )
            )
    }
}

extension Color {
    static let pkBackground = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let pkSurface = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let pkSidebar = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let pkCard = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let pkElevated = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let pkStroke = Color(red: 0.24, green: 0.25, blue: 0.28)
    static let pkMuted = Color(red: 0.71, green: 0.73, blue: 0.78)
    static let pkText = Color(red: 0.91, green: 0.91, blue: 0.92)
    static let pkPrimary = Color(red: 0.52, green: 0.68, blue: 1.00)
    static let pkOnPrimary = Color(red: 0.00, green: 0.16, blue: 0.36)
    static let pkSuccess = Color(red: 0.30, green: 0.87, blue: 0.40)
    static let pkSecondary = Color(red: 0.30, green: 0.87, blue: 0.40)
    static let pkWarning = Color(red: 1.00, green: 0.70, blue: 0.65)
    static let pkDanger = Color(red: 0.68, green: 0.02, blue: 0.08)
    static let pkDangerText = Color(red: 1.00, green: 0.85, blue: 0.84)
}

#Preview {
    ContentView()
        .environmentObject(PortViewModel())
        .frame(width: 1360, height: 960)
}

#Preview("Menu Bar") {
    MenuBarPopoverView()
        .environmentObject(PortViewModel())
}
