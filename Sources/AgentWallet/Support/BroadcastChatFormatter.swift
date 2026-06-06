import Foundation

enum BroadcastAction: Equatable {
    case swapApproval(spendSymbol: String)
    case swap
    case transfer
}

enum BroadcastChatFormatter {
    static func formatSuccess(
        action: BroadcastAction,
        hash: String,
        chain: ChainProfile
    ) -> String {
        let shortHash = JSONPrettyPrinter.shortHash(hash)
        let url = "\(chain.explorerTransactionURLPrefix)/\(hash)"
        let header: String
        switch action {
        case .swapApproval(let symbol):
            header = "已在 \(chain.displayName) 上广播 \(symbol) 授权交易。授权上链后再来生成最新报价，然后签名兑换。"
        case .swap:
            header = "已在 \(chain.displayName) 上完成 Uniswap 兑换。"
        case .transfer:
            header = "已在 \(chain.displayName) 上广播转账。"
        }
        return [
            header,
            "交易哈希：\(shortHash)",
            url
        ].joined(separator: "\n")
    }
}
