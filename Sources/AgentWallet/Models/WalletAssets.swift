import Foundation

struct WalletTokenBalance: Identifiable, Equatable {
    let symbol: String
    let name: String?
    let balance: String
    let usdValue: String?
    let address: String?

    var id: String {
        [symbol, address ?? name ?? balance].joined(separator: "|")
    }

    var displayName: String {
        if let name, !name.isEmpty, name != symbol {
            return "\(symbol) · \(name)"
        }

        return symbol
    }
}

struct WalletChainTokenAssets: Equatable {
    let chain: ChainProfile
    let tokens: [WalletTokenBalance]
    let totalUSD: String?
    let errorMessage: String?
    let updatedAt: Date
}

struct WalletChainAssets: Identifiable, Equatable {
    let chain: ChainProfile
    let gasBalance: LocalWalletBalance?
    let gasErrorMessage: String?
    let tokens: [WalletTokenBalance]
    let totalUSD: String?
    let tokenErrorMessage: String?
    let updatedAt: Date

    var id: String {
        chain.id
    }

    var hasGas: Bool {
        gasBalance?.hasGas == true
    }

    var gasText: String {
        if let gasBalance {
            return gasBalance.formattedNativeBalance
        }

        if gasErrorMessage != nil {
            return "读取失败"
        }

        return "未刷新"
    }

    var assetSummary: String {
        let tokenCount = tokens.count
        if let totalUSD, tokenCount > 0 {
            return "\(tokenCount) 个代币 · \(totalUSD)"
        }

        if tokenCount > 0 {
            return "\(tokenCount) 个代币"
        }

        return "未发现代币"
    }
}
