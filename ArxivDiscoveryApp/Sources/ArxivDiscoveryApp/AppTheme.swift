import SwiftUI

enum AppTheme {
    static let sky = Color(red: 130.0 / 255.0, green: 199.0 / 255.0, blue: 238.0 / 255.0)
    static let skyInk = Color(red: 18.0 / 255.0, green: 95.0 / 255.0, blue: 132.0 / 255.0)
    static let teal = Color(red: 63.0 / 255.0, green: 166.0 / 255.0, blue: 160.0 / 255.0)
    static let orange = Color(red: 232.0 / 255.0, green: 137.0 / 255.0, blue: 69.0 / 255.0)
    static let nearBlack = Color(red: 17.0 / 255.0, green: 21.0 / 255.0, blue: 27.0 / 255.0)
    static let charcoal = Color(red: 24.0 / 255.0, green: 30.0 / 255.0, blue: 38.0 / 255.0)
    static let blueGray = Color(red: 34.0 / 255.0, green: 43.0 / 255.0, blue: 56.0 / 255.0)

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? nearBlack : Color(nsColor: .windowBackgroundColor)
    }

    static func panel(for scheme: ColorScheme) -> Color {
        scheme == .dark ? charcoal : Color(nsColor: .controlBackgroundColor)
    }

    static func raised(for scheme: ColorScheme) -> Color {
        scheme == .dark ? blueGray : Color(nsColor: .textBackgroundColor)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.16)
    }
}

struct PixelPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .background(AppTheme.panel(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(emphasized ? AppTheme.sky : AppTheme.border(for: colorScheme), lineWidth: emphasized ? 2 : 1)
            }
    }
}

extension View {
    func pixelPanel(emphasized: Bool = false) -> some View {
        modifier(PixelPanelModifier(emphasized: emphasized))
    }
}
