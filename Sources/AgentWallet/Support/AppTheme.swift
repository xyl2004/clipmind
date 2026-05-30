import SwiftUI

enum AppTheme {
    static let canvasTop = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let canvasBottom = Color(red: 0.93, green: 0.92, blue: 0.88)
    static let panel = Color.white.opacity(0.86)
    static let panelSoft = Color.white.opacity(0.60)
    static let border = Color.black.opacity(0.12)
    static let accent = Color(red: 0.40, green: 0.70, blue: 0.20)
    static let cyan = Color(red: 0.08, green: 0.55, blue: 0.55)
    static let rose = Color(red: 0.85, green: 0.25, blue: 0.42)
    static let primaryText = Color(red: 0.10, green: 0.11, blue: 0.10)
    static let mutedText = Color.black.opacity(0.58)

    static var background: some View {
        LinearGradient(
            colors: [canvasTop, canvasBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            AppTheme.cyan.opacity(0.06)
                .blur(radius: 90)
                .offset(x: -300, y: -220)
        )
        .overlay(
            AppTheme.accent.opacity(0.06)
                .blur(radius: 80)
                .offset(x: 320, y: 240)
        )
    }
}

struct ProductPanel: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

struct ProductButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : AppTheme.primaryText.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? AppTheme.accent : AppTheme.panelSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(prominent ? Color.clear : AppTheme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

extension View {
    func productPanel(padding: CGFloat = 16) -> some View {
        modifier(ProductPanel(padding: padding))
    }
}
