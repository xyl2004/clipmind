import Foundation

struct TradeIntentDraft {
    var spendAmount: String = "20"
    var tokenAddress: String = ""
    var slippage: Double = 1.0
    var recipientAddress: String = ""

    var canBuildSwapPlan: Bool {
        !spendAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && QueryClassifier.isAddress(tokenAddress.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var canBuildTransferPlan: Bool {
        !spendAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && QueryClassifier.isAddress(recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
