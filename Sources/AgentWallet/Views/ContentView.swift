import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store)
                .frame(width: 282)

            VStack(spacing: 0) {
                QueryComposerView(store: store)

                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let errorMessage = store.errorMessage {
                            StatusBanner(
                                title: "需要处理",
                                message: errorMessage,
                                systemImage: "exclamationmark.triangle",
                                tint: .orange
                            )
                        }

                        ContextChatView(store: store)

                        if let result = store.result {
                            ResearchResultView(
                                snapshot: result,
                                aiExplanation: store.aiExplanation,
                                isExplaining: store.isExplaining,
                                llmErrorMessage: store.llmErrorMessage
                            ) {
                                Task {
                                    await store.runLLMExplanation()
                                }
                            }
                        } else {
                            EmptyResearchView()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
    }
}
