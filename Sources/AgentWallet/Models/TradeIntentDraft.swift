import Foundation

struct TradeIntentDraft {
    var spendAmount: String = "20"
    var spendTokenSymbol: String = "USDC"
    var spendTokenAddress: String = ChainRegistry.base.defaultSpendToken.address
    var spendTokenDecimals: Int = ChainRegistry.base.defaultSpendToken.decimals
    var tokenAddress: String = ""
    var slippage: Double = 1.0
    var recipientAddress: String = ""

    var canBuildSwapPlan: Bool {
        !spendAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isValidSpendToken
            && QueryClassifier.isAddress(tokenAddress.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var canBuildTransferPlan: Bool {
        !spendAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && QueryClassifier.isAddress(recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func applyDefaultSpendToken(for chain: ChainProfile) {
        spendTokenSymbol = chain.defaultSpendToken.symbol
        spendTokenAddress = chain.defaultSpendToken.address
        spendTokenDecimals = chain.defaultSpendToken.decimals
    }

    private var isValidSpendToken: Bool {
        let address = spendTokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.lowercased() == TokenProfile.nativeETH.address.lowercased()
            || QueryClassifier.isAddress(address)
    }
}
