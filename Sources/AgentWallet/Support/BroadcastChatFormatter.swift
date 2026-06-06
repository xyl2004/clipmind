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

extension BroadcastChatFormatter {
    static func formatFailure(action: BroadcastAction, error: Error) -> String {
        let actionLabel: String
        let hint: String
        switch action {
        case .swapApproval:
            actionLabel = "广播授权失败"
            hint = "可以检查 Gas 余额和网络后再试。"
        case .swap:
            actionLabel = "广播 Uniswap 兑换失败"
            hint = "可以检查 Gas 余额、报价新鲜度、网络后再试。"
        case .transfer:
            actionLabel = "广播转账失败"
            hint = "可以检查 Gas 余额、收款地址和网络后再试。"
        }
        return "\(actionLabel)：\(error.localizedDescription)。\n\(hint)"
    }
}
