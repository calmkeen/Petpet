import SwiftUI

/// Overview pages never scroll: the Crown belongs to the section pager.
/// Drop secondary detail before squeezing text or the primary action.
struct WatchOverviewLayout<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(false).fixedSize(horizontal: false, vertical: true)
            content(true).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WatchActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var color: Color = .cyan
    var backgroundOpacity = 0.24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .background(color.opacity(enabled ? (configuration.isPressed ? min(1, backgroundOpacity + 0.16) : backgroundOpacity) : 0.08), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
    }
}

struct WatchStatisticButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.bold())
            .frame(width: 44, height: 44)
            .foregroundStyle(enabled ? Color.cyan : Color.secondary)
            .background(Color.cyan.opacity(enabled ? (configuration.isPressed ? 0.35 : 0.18) : 0.06), in: Circle())
            .contentShape(Rectangle())
    }
}

/// Abbreviations are for overviews only; detail screens and VoiceOver retain exact values.
enum WatchNumber {
    static func compact(_ value: Int64) -> String {
        guard value >= 10_000 || value <= -10_000 else { return value.formatted() }
        let compact = value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        return compact.count <= 7 ? compact : value.formatted(.number.notation(.scientific).precision(.significantDigits(2)))
    }
}
