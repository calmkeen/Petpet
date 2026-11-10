import SwiftUI

/// Match the watch's cyan accents and rounded controls while retaining
/// readable contrast on both light and dark iPhone surfaces.
enum PhoneDesign {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.83, blue: 0.95, alpha: 1)
            : UIColor(red: 0, green: 0.36, blue: 0.48, alpha: 1)
    })
    static let actionFill = Color(red: 0, green: 0.36, blue: 0.48)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct PhoneCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(PhoneDesign.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct PhoneActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let fill = configuration.role == .destructive ? Color(red: 0.72, green: 0.12, blue: 0.16) : PhoneDesign.actionFill
        return configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .background(enabled ? fill.opacity(configuration.isPressed ? 0.75 : 1) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
    }
}

struct PhoneIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .frame(width: 44, height: 44)
            .foregroundStyle(enabled ? PhoneDesign.accent : Color.secondary)
            .background(PhoneDesign.accent.opacity(configuration.isPressed ? 0.22 : 0.10), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
    }
}

struct PhoneSectionTitle: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(PhoneDesign.accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PhoneSectionSwitchStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? Color.white : PhoneDesign.accent)
            .background(selected ? PhoneDesign.actionFill : PhoneDesign.surface, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}
