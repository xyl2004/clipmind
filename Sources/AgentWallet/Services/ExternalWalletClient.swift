import Foundation

struct ExternalWalletSession: Equatable {
    let address: String
    let connectedAt: Date

    var shortAddress: String {
        JSONPrettyPrinter.shortAddress(address)
    }
}

struct ExternalWalletClient {
    func connect(address: String) throws -> ExternalWalletSession {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard QueryClassifier.isAddress(trimmed) else {
            throw ExternalWalletError.invalidAddress
        }

        return ExternalWalletSession(address: trimmed, connectedAt: Date())
    }

    func send(_ transaction: EVMTransactionRequest) async throws -> String {
        guard !transaction.to.isEmpty else {
            throw ExternalWalletError.invalidTransaction
        }

        throw ExternalWalletError.walletConnectNotConfigured
    }
}

enum ExternalWalletError: LocalizedError {
    case invalidAddress
    case invalidTransaction
    case walletConnectNotConfigured
    case userRejected

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "请输入有效的外部钱包地址。"
        case .invalidTransaction:
            "交易请求无效，无法发送给外部钱包。"
        case .walletConnectNotConfigured:
            "交易已生成，但当前版本尚未接入 WalletConnect SDK，不能弹出外部钱包签名。"
        case .userRejected:
            "用户取消签名。"
        }
    }
}
