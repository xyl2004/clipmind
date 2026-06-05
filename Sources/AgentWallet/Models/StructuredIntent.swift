import Foundation

enum StructuredIntentAction: String, CaseIterable, Equatable {
    case ask
    case transfer
    case swap
    case unsupported
    case checkBalance = "check_balance"
    case checkToken = "check_token"
    case checkTx = "check_tx"
    case checkAddress = "check_address"
}

struct StructuredIntent: Equatable {
    let action: StructuredIntentAction
    let chain: String?
    let targetAddress: String
    let targetQuery: String
    let transactionHash: String
    let spendAssetSymbol: String
    let spendAmount: String
    let slippagePercent: Double?
    let unsupportedReason: String

    static func empty(action: StructuredIntentAction) -> StructuredIntent {
        StructuredIntent(
            action: action,
            chain: nil,
            targetAddress: "",
            targetQuery: "",
            transactionHash: "",
            spendAssetSymbol: "",
            spendAmount: "",
            slippagePercent: nil,
            unsupportedReason: ""
        )
    }
}
