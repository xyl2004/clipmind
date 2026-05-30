import SwiftUI

struct FloatingContextPanelView: View {
    @ObservedObject var store: AppStore
    let onClose: () -> Void
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                ContextChatView(store: store)
                    .padding(14)
            }
        }
        .frame(width: 620)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.36), radius: 28, x: 0, y: 14)
        .padding(8)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: FloatingPanelSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(FloatingPanelSizePreferenceKey.self) { size in
            onSizeChange(size)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("AgentWallet", systemImage: "wallet.pass")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            Text("⌃⌥W")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.mutedText)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.clear)
    }
}

private struct FloatingPanelSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
