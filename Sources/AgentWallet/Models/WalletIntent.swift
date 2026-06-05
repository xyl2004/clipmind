import BigInt
import Foundation

enum WalletIntentAction: String {
    case ask
    case transfer
    case swap
    case unsupported

    var title: String {
        switch self {
        case .ask:
            return "问答"
        case .transfer:
            return "转账"
        case .swap:
            return "买币"
        case .unsupported:
            return "暂不支持"
        }
    }
}

struct WalletIntentDraft: Identifiable, Equatable {
    let id = UUID()
    let action: WalletIntentAction
    let selectedContext: String
    let targetAddress: String
    let targetQuery: String
    let chain: ChainProfile
    let spendAsset: TokenProfile
    let spendAmount: String
    let recipientAddress: String
    let slippage: Double
    let missingFields: [String]
    let riskNotes: [String]
    let confirmationSummary: String

    var requiresConfirmation: Bool {
        action == .transfer || action == .swap
    }

    var isComplete: Bool {
        missingFields.isEmpty && (action == .transfer || action == .swap)
    }

    var missingFieldsText: String {
        missingFields.isEmpty ? "无" : missingFields.joined(separator: "、")
    }
}

struct TransferPlan: Identifiable {
    static let validitySeconds: TimeInterval = 120

    let id = UUID()
    let createdAt: Date
    let expiresAt: Date
    let chain: ChainProfile
    let walletAddress: String
    let recipientAddress: String
    let asset: TokenProfile
    let amount: String
    let amountBaseUnits: String
    let transaction: EVMTransactionRequest
    let requiresCalldata: Bool
    let safetyChecks: [String]

    var confirmationCode: String {
        String(recipientAddress.suffix(4)).uppercased()
    }

    var isFreshForSigning: Bool {
        isFresh(at: Date())
    }

    var freshnessStatus: String {
        if isFreshForSigning {
            return "约 \(max(0, Int(expiresAt.timeIntervalSinceNow.rounded(.down)))) 秒内有效"
        }

        return "已过期，请重新生成"
    }

    func isFresh(at date: Date) -> Bool {
        date < expiresAt
    }
}

enum WalletIntentParser {
    static func parse(
        selectedText: String,
        question: String,
        chain: ChainProfile,
        continuing previousIntent: WalletIntentDraft? = nil
    ) -> WalletIntentDraft {
        let selectedContext = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedQuestion = normalizedQuestion.lowercased()

        let selectedAddress = QueryClassifier.isAddress(selectedContext) ? selectedContext : ""
        let inlineAddress = firstAddress(in: normalizedQuestion)
        let amountMatch = extractAmount(from: normalizedQuestion)

        if !isSwapIntent(lowercasedQuestion),
           !isTransferIntent(lowercasedQuestion),
           let continuation = continuationSwapIntent(
            previousIntent: previousIntent,
            selectedContext: selectedContext,
            amountMatch: amountMatch,
            chain: chain
           ) {
            return continuation
        }

        if isSwapIntent(lowercasedQuestion) {
            let targetAddress = selectedAddress.isEmpty ? inlineAddress : selectedAddress
            let targetQuery = tokenSearchQuery(
                selectedContext: selectedContext,
                question: normalizedQuestion,
                targetAddress: targetAddress
            )
            let spendAsset = tokenProfile(
                symbolHint: amountMatch.symbol,
                chain: chain,
                defaultForSwap: true
            )
            var missingFields: [String] = []
            if targetAddress.isEmpty && targetQuery.isEmpty {
                missingFields.append("目标代币地址或名称")
            }
            if amountMatch.amount.isEmpty {
                missingFields.append("支付金额")
            }
            if spendAsset == nil {
                missingFields.append("支付资产")
            }

            let asset = spendAsset ?? chain.defaultSpendToken
            return WalletIntentDraft(
                action: .swap,
                selectedContext: selectedContext,
                targetAddress: targetAddress,
                targetQuery: targetQuery,
                chain: chain,
                spendAsset: asset,
                spendAmount: amountMatch.amount,
                recipientAddress: "",
                slippage: 1.0,
                missingFields: missingFields,
                riskNotes: [
                    "AI 只生成计划，不会签名或广播。",
                    "Uniswap 报价过期后必须重新生成。",
                    "签名前需要核对目标代币合约和支付金额。"
                ],
                confirmationSummary: "准备在 \(chain.displayName) 用 \(amountMatch.amount.isEmpty ? "待补充" : amountMatch.amount) \(asset.symbol) 购买 \(swapTargetSummary(address: targetAddress, query: targetQuery))。"
            )
        }

        if isTransferIntent(lowercasedQuestion) {
            let recipientAddress = selectedAddress.isEmpty ? inlineAddress : selectedAddress
            let spendAsset = tokenProfile(
                symbolHint: amountMatch.symbol,
                chain: chain,
                defaultForSwap: false
            )
            var missingFields: [String] = []
            if recipientAddress.isEmpty {
                missingFields.append("收款地址")
            }
            if amountMatch.amount.isEmpty {
                missingFields.append("转账金额")
            }
            if spendAsset == nil {
                missingFields.append("转账资产")
            }

            let asset = spendAsset ?? chain.defaultSpendToken
            return WalletIntentDraft(
                action: .transfer,
                selectedContext: selectedContext,
                targetAddress: recipientAddress,
                targetQuery: "",
                chain: chain,
                spendAsset: asset,
                spendAmount: amountMatch.amount,
                recipientAddress: recipientAddress,
                slippage: 0,
                missingFields: missingFields,
                riskNotes: [
                    "AI 只生成计划，不会签名或广播。",
                    "请确认收款地址不可撤销。",
                    "签名前需要输入收款地址后 4 位。"
                ],
                confirmationSummary: "准备在 \(chain.displayName) 向 \(recipientAddress.isEmpty ? "待补充地址" : JSONPrettyPrinter.shortAddress(recipientAddress)) 转账 \(amountMatch.amount.isEmpty ? "待补充" : amountMatch.amount) \(asset.symbol)。"
            )
        }

        return WalletIntentDraft(
            action: .ask,
            selectedContext: selectedContext,
            targetAddress: selectedAddress,
            targetQuery: "",
            chain: chain,
            spendAsset: chain.defaultSpendToken,
            spendAmount: "",
            recipientAddress: "",
            slippage: 0,
            missingFields: [],
            riskNotes: [],
            confirmationSummary: ""
        )
    }

    private static func isSwapIntent(_ value: String) -> Bool {
        containsAny(value, tokens: ["买", "购买", "兑换", "换成", "swap", "buy"])
    }

    private static func isTransferIntent(_ value: String) -> Bool {
        containsAny(value, tokens: ["转账", "转给", "转 ", "发送", "打给", "打款", "send", "transfer"])
            || (value.contains("给") && value.contains("转"))
    }

    private static func containsAny(_ value: String, tokens: [String]) -> Bool {
        tokens.contains { value.contains($0) }
    }

    private static func tokenSearchQuery(
        selectedContext: String,
        question: String,
        targetAddress: String
    ) -> String {
        if !targetAddress.isEmpty {
            return ""
        }

        let selected = selectedContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedSelected = normalizedTokenName(selected) {
            return normalizedSelected
        }

        let markers = ["买", "购买", "兑换", "换成", "swap", "buy"]
        for marker in markers {
            guard let range = question.range(of: marker, options: [.caseInsensitive]) else {
                continue
            }

            let suffix = String(question[range.upperBound...])
                .replacingOccurrences(of: "这个代币", with: "")
                .replacingOccurrences(of: "这个币", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let words = suffix.split { character in
                character.isWhitespace || character == "," || character == "，" || character == "." || character == "。"
            }
            if let word = words.first.map(String.init),
               let normalizedWord = normalizedTokenName(word) {
                return normalizedWord
            }
        }

        return ""
    }

    private static func normalizedTokenName(_ value: String) -> String? {
        let trimmed = QueryClassifier.normalizedLookupText(value)
        guard !trimmed.isEmpty, trimmed.count <= 32 else {
            return nil
        }

        if QueryClassifier.isAddress(trimmed) || QueryClassifier.isTransactionHash(trimmed) {
            return nil
        }

        guard trimmed.allSatisfy({ character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }) else {
            return nil
        }

        return trimmed
    }

    private static func swapTargetSummary(address: String, query: String) -> String {
        if !address.isEmpty {
            return JSONPrettyPrinter.shortAddress(address)
        }

        if !query.isEmpty {
            return "\(query)（待确认合约）"
        }

        return "待补充代币"
    }

    private static func firstAddress(in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "0x[a-fA-F0-9]{40}") else {
            return ""
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let swiftRange = Range(match.range, in: value) else {
            return ""
        }

        return String(value[swiftRange])
    }

    private static func extractAmount(from value: String) -> (amount: String, symbol: String) {
        let pattern = "([0-9]+(?:[\\.,][0-9]+)?)[\\s]*(usdc|u|eth|weth)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ("", "")
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let amountRange = Range(match.range(at: 1), in: value) else {
                continue
            }

            let amount = String(value[amountRange]).replacingOccurrences(of: ",", with: ".")
            let prefixIndex = amountRange.lowerBound
            if prefixIndex > value.startIndex {
                let previous = value[value.index(before: prefixIndex)]
                let previousValue = String(previous).lowercased()
                if previousValue == "x" || ["a", "b", "c", "d", "e", "f"].contains(previousValue) {
                    continue
                }
            }
            let suffixIndex = amountRange.upperBound
            if suffixIndex < value.endIndex {
                let next = value[suffixIndex]
                if next == "x" || next == "X" {
                    continue
                }
            }

            var symbol = ""
            if match.numberOfRanges >= 3,
               match.range(at: 2).location != NSNotFound,
               let symbolRange = Range(match.range(at: 2), in: value) {
                symbol = String(value[symbolRange]).uppercased()
                if symbol == "U" {
                    symbol = "USDC"
                }
            }
            return (amount, symbol)
        }

        return ("", "")
    }

    private static func continuationSwapIntent(
        previousIntent: WalletIntentDraft?,
        selectedContext: String,
        amountMatch: (amount: String, symbol: String),
        chain: ChainProfile
    ) -> WalletIntentDraft? {
        guard let previousIntent,
              previousIntent.action == .swap,
              previousIntent.missingFields.contains("支付金额"),
              !amountMatch.amount.isEmpty,
              !previousIntent.targetAddress.isEmpty || !previousIntent.targetQuery.isEmpty else {
            return nil
        }

        let spendAsset = tokenProfile(
            symbolHint: amountMatch.symbol,
            chain: chain,
            defaultForSwap: true
        )
        var missingFields: [String] = []
        if spendAsset == nil {
            missingFields.append("支付资产")
        }

        let asset = spendAsset ?? chain.defaultSpendToken
        let context = previousIntent.selectedContext.isEmpty ? selectedContext : previousIntent.selectedContext
        return WalletIntentDraft(
            action: .swap,
            selectedContext: context,
            targetAddress: previousIntent.targetAddress,
            targetQuery: previousIntent.targetQuery,
            chain: chain,
            spendAsset: asset,
            spendAmount: amountMatch.amount,
            recipientAddress: "",
            slippage: previousIntent.slippage,
            missingFields: missingFields,
            riskNotes: previousIntent.riskNotes,
            confirmationSummary: "准备在 \(chain.displayName) 用 \(amountMatch.amount) \(asset.symbol) 购买 \(swapTargetSummary(address: previousIntent.targetAddress, query: previousIntent.targetQuery))。"
        )
    }

    private static func tokenProfile(
        symbolHint: String,
        chain: ChainProfile,
        defaultForSwap: Bool
    ) -> TokenProfile? {
        let normalized = symbolHint.uppercased()
        if normalized == "ETH" {
            return .nativeETH
        }

        if normalized == "USDC" || (normalized.isEmpty && defaultForSwap) {
            if chain.defaultSpendToken.symbol.uppercased() == "USDC" {
                return chain.defaultSpendToken
            }

            if normalized.isEmpty {
                return chain.defaultSpendToken
            }
        }

        if normalized.isEmpty {
            return nil
        }

        return nil
    }
}

enum TransferPlanBuilder {
    static func build(
        intent: WalletIntentDraft,
        account: LocalWalletAccount
    ) throws -> TransferPlan {
        guard intent.action == .transfer else {
            throw WalletIntentError.unsupportedAction
        }

        let recipient = intent.recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard QueryClassifier.isAddress(recipient) else {
            throw WalletIntentError.invalidAddress
        }

        let baseUnits = try TokenAmountParser.baseUnits(
            amount: intent.spendAmount,
            decimals: intent.spendAsset.decimals
        )
        let isNative = intent.spendAsset.address.lowercased() == TokenProfile.nativeETH.address.lowercased()
        let transaction: EVMTransactionRequest

        if isNative {
            transaction = EVMTransactionRequest(
                to: recipient,
                from: account.address,
                data: nil,
                value: baseUnits,
                gasLimit: nil,
                chainID: intent.chain.chainID,
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil,
                gasPrice: nil
            )
        } else {
            transaction = EVMTransactionRequest(
                to: intent.spendAsset.address,
                from: account.address,
                data: erc20TransferCalldata(recipient: recipient, amountBaseUnits: baseUnits),
                value: "0",
                gasLimit: nil,
                chainID: intent.chain.chainID,
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil,
                gasPrice: nil
            )
        }

        let createdAt = Date()
        return TransferPlan(
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(TransferPlan.validitySeconds),
            chain: intent.chain,
            walletAddress: account.address,
            recipientAddress: recipient,
            asset: intent.spendAsset,
            amount: intent.spendAmount,
            amountBaseUnits: baseUnits,
            transaction: transaction,
            requiresCalldata: !isNative,
            safetyChecks: [
                "收款地址格式已校验。",
                isNative ? "原生 \(intent.chain.nativeTokenSymbol) 转账将直接发送到收款地址。" : "ERC-20 转账将调用 token 合约 transfer。",
                "签名前需要输入收款地址后 4 位确认。",
                "Gas 会在本机签名前由 RPC 估算。"
            ]
        )
    }

    private static func erc20TransferCalldata(recipient: String, amountBaseUnits: String) -> String {
        let cleanRecipient = recipient.lowercased().replacingOccurrences(of: "0x", with: "")
        let recipientWord = String(repeating: "0", count: max(0, 64 - cleanRecipient.count)) + cleanRecipient
        let amount = BigUInt(amountBaseUnits, radix: 10) ?? 0
        let amountHex = String(amount, radix: 16)
        let amountWord = String(repeating: "0", count: max(0, 64 - amountHex.count)) + amountHex
        return "0xa9059cbb\(recipientWord)\(amountWord)"
    }
}

enum TokenAmountParser {
    static func baseUnits(amount: String, decimals: Int) throws -> String {
        let normalized = amount
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else {
            throw WalletIntentError.invalidAmount
        }

        let pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2,
              pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            throw WalletIntentError.invalidAmount
        }

        let whole = String(pieces.first ?? "0")
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= decimals else {
            throw WalletIntentError.invalidAmount
        }

        let paddedFraction = fraction + String(repeating: "0", count: decimals - fraction.count)
        let combined = (whole + paddedFraction).drop(while: { $0 == "0" })
        let value = combined.isEmpty ? "0" : String(combined)
        guard value != "0" else {
            throw WalletIntentError.invalidAmount
        }
        return value
    }
}

enum WalletIntentError: LocalizedError {
    case unsupportedAction
    case invalidAddress
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .unsupportedAction:
            return "暂不支持这个钱包操作。"
        case .invalidAddress:
            return "地址格式无效。"
        case .invalidAmount:
            return "金额格式无效，请输入大于 0 的数字。"
        }
    }
}
