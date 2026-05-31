import Foundation

struct UniswapTradePlan: Identifiable {
    let id = UUID()
    let chain: ChainProfile
    let walletAddress: String
    let inputToken: TokenProfile
    let outputTokenAddress: String
    let inputAmount: String
    let inputAmountBaseUnits: String
    let slippageTolerance: Double
    let approvalTransaction: EVMTransactionRequest?
    let approvalGasFee: String?
    let quoteRequestID: String?
    let routing: String
    let outputAmount: String?
    let gasFee: String?
    let swapTransaction: EVMTransactionRequest?
    let rawQuoteJSON: String
    let rawSwapJSON: String?

    var needsApproval: Bool {
        approvalTransaction?.hasCalldata == true
    }
}

struct EVMTransactionRequest: Hashable {
    let to: String
    let from: String?
    let data: String?
    let value: String?
    let gasLimit: String?
    let chainID: Int?
    let maxFeePerGas: String?
    let maxPriorityFeePerGas: String?
    let gasPrice: String?

    var hasCalldata: Bool {
        guard let data else {
            return false
        }
        return data != "0x" && !data.isEmpty
    }

    var shortTo: String {
        JSONPrettyPrinter.shortAddress(to)
    }

    init?(_ object: Any?) {
        guard let dictionary = object as? [String: Any],
              let to = dictionary["to"] as? String,
              !to.isEmpty else {
            return nil
        }

        self.to = to
        self.from = dictionary["from"] as? String
        self.data = dictionary["data"] as? String
        self.value = dictionary["value"].map { "\($0)" }
        self.gasLimit = dictionary["gasLimit"].map { "\($0)" }
        self.chainID = dictionary["chainId"] as? Int ?? (dictionary["chainId"] as? NSNumber)?.intValue
        self.maxFeePerGas = dictionary["maxFeePerGas"].map { "\($0)" }
        self.maxPriorityFeePerGas = dictionary["maxPriorityFeePerGas"].map { "\($0)" }
        self.gasPrice = dictionary["gasPrice"].map { "\($0)" }
    }
}

protocol TradeProvider {
    func buildSwapPlan(
        draft: TradeIntentDraft,
        chain: ChainProfile,
        walletAddress: String
    ) async throws -> UniswapTradePlan
}

struct UniswapTradeProvider: TradeProvider {
    private static let defaultBaseURL = URL(string: "https://trade-api.gateway.uniswap.org/v1")!
    private static let baseURLOverrideEnv = "AGENTWALLET_UNISWAP_BASE_URL"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var baseURL: URL {
        ProcessInfo.processInfo.environment[Self.baseURLOverrideEnv]
            .flatMap { URL(string: $0) }
            ?? Self.defaultBaseURL
    }

    func buildSwapPlan(
        draft: TradeIntentDraft,
        chain: ChainProfile,
        walletAddress: String
    ) async throws -> UniswapTradePlan {
        guard chain.supportsSwap else {
            throw UniswapTradeError.unsupportedChain(chain.displayName)
        }

        let trimmedWallet = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard QueryClassifier.isAddress(trimmedWallet) else {
            throw UniswapTradeError.invalidWallet
        }

        let outputToken = draft.tokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard QueryClassifier.isAddress(outputToken) else {
            throw UniswapTradeError.invalidToken
        }

        let inputTokenAddress = draft.spendTokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNativeInput = inputTokenAddress.lowercased() == TokenProfile.nativeETH.address.lowercased()
        guard isNativeInput || QueryClassifier.isAddress(inputTokenAddress) else {
            throw UniswapTradeError.invalidSpendToken
        }

        let amountBaseUnits = try Self.baseUnits(
            amount: draft.spendAmount,
            decimals: draft.spendTokenDecimals
        )
        let inputToken = TokenProfile(
            symbol: draft.spendTokenSymbol.isEmpty ? "TOKEN" : draft.spendTokenSymbol,
            address: inputTokenAddress,
            decimals: draft.spendTokenDecimals
        )

        let approvalObject: [String: Any]
        if isNativeInput {
            approvalObject = [:]
        } else {
            approvalObject = try await post(
                endpoint: "check_approval",
                body: [
                    "walletAddress": trimmedWallet,
                    "token": inputTokenAddress,
                    "amount": amountBaseUnits,
                    "chainId": chain.chainID
                ],
                includeRouterVersion: false
            )
        }

        let quoteObject = try await post(
            endpoint: "quote",
            body: [
                "type": "EXACT_INPUT",
                "tokenIn": inputTokenAddress,
                "tokenOut": outputToken,
                "tokenInChainId": chain.chainID,
                "tokenOutChainId": chain.chainID,
                "amount": amountBaseUnits,
                "swapper": trimmedWallet,
                "slippageTolerance": draft.slippage,
                "routingPreference": "BEST_PRICE",
                "protocols": ["V2", "V3", "V4"]
            ],
            includeRouterVersion: true
        )

        let quote = quoteObject["quote"] as? [String: Any] ?? [:]
        let swapObject = try await post(
            endpoint: "swap",
            body: [
                "quote": quote,
                "refreshGasPrice": true,
                "simulateTransaction": false,
                "safetyMode": "SAFE"
            ],
            includeRouterVersion: true
        )

        return UniswapTradePlan(
            chain: chain,
            walletAddress: trimmedWallet,
            inputToken: inputToken,
            outputTokenAddress: outputToken,
            inputAmount: draft.spendAmount,
            inputAmountBaseUnits: amountBaseUnits,
            slippageTolerance: draft.slippage,
            approvalTransaction: EVMTransactionRequest(approvalObject["approval"]),
            approvalGasFee: approvalObject["gasFee"].map { "\($0)" },
            quoteRequestID: quoteObject["requestId"] as? String,
            routing: quoteObject["routing"] as? String ?? "CLASSIC",
            outputAmount: Self.extractOutputAmount(from: quoteObject),
            gasFee: swapObject["gasFee"].map { "\($0)" } ?? quoteObject["gasFee"].map { "\($0)" },
            swapTransaction: EVMTransactionRequest(swapObject["swap"]),
            rawQuoteJSON: JSONPrettyPrinter.prettyString(quoteObject) ?? "\(quoteObject)",
            rawSwapJSON: JSONPrettyPrinter.prettyString(swapObject)
        )
    }

    private func post(
        endpoint: String,
        body: [String: Any],
        includeRouterVersion: Bool
    ) async throws -> [String: Any] {
        guard let apiKey = CredentialStore.readUniswapAPIKey() else {
            throw UniswapTradeError.missingAPIKey
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("true", forHTTPHeaderField: "x-permit2-disabled")
        if includeRouterVersion {
            request.setValue("2.0", forHTTPHeaderField: "x-universal-router-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UniswapTradeError.invalidResponse
        }

        guard let object = JSONPrettyPrinter.parse(String(data: data, encoding: .utf8) ?? "") as? [String: Any] else {
            throw UniswapTradeError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                CredentialStore.clearUniswapAPIKey()
                throw UniswapTradeError.apiError("Uniswap API Key 无效，请重新保存。")
            }
            throw UniswapTradeError.apiError(Self.errorMessage(from: object) ?? "HTTP \(httpResponse.statusCode)")
        }

        return object
    }

    private static func baseUnits(amount: String, decimals: Int) throws -> String {
        let normalized = amount
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else {
            throw UniswapTradeError.invalidAmount
        }

        let pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2,
              pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            throw UniswapTradeError.invalidAmount
        }

        let whole = String(pieces.first ?? "0")
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= decimals else {
            throw UniswapTradeError.invalidAmount
        }

        let paddedFraction = fraction + String(repeating: "0", count: decimals - fraction.count)
        let combined = (whole + paddedFraction).drop(while: { $0 == "0" })
        let value = combined.isEmpty ? "0" : String(combined)
        guard value != "0" else {
            throw UniswapTradeError.invalidAmount
        }
        return value
    }

    private static func extractOutputAmount(from object: [String: Any]) -> String? {
        guard let quote = object["quote"] as? [String: Any] else {
            return nil
        }

        if let orderInfo = quote["orderInfo"] as? [String: Any],
           let outputs = orderInfo["outputs"] as? [[String: Any]],
           let first = outputs.first {
            return first["endAmount"].map { "\($0)" } ?? first["startAmount"].map { "\($0)" }
        }

        if let outputs = quote["outputs"] as? [[String: Any]],
           let first = outputs.first {
            return first["amount"].map { "\($0)" } ?? first["endAmount"].map { "\($0)" }
        }

        return quote["outputAmount"].map { "\($0)" }
    }

    private static func errorMessage(from object: [String: Any]) -> String? {
        if let detail = object["detail"] as? String {
            return detail
        }
        if let message = object["message"] as? String {
            return message
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }
}

enum UniswapTradeError: LocalizedError {
    case missingAPIKey
    case invalidWallet
    case invalidToken
    case invalidSpendToken
    case invalidAmount
    case unsupportedChain(String)
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "未设置 Uniswap API Key。请保存到 Keychain，或设置 AGENTWALLET_UNISWAP_API_KEY / UNISWAP_API_KEY。"
        case .invalidWallet:
            "请先创建或导入一个有效的本地 EVM 钱包。"
        case .invalidToken:
            "目标代币地址不是有效的 EVM 地址。"
        case .invalidSpendToken:
            "支付资产地址不是有效的 EVM 地址。"
        case .invalidAmount:
            "交易金额格式无效，请输入大于 0 的数字。"
        case .unsupportedChain(let chain):
            "\(chain) 暂不支持 Uniswap swap。"
        case .invalidResponse:
            "Uniswap API 返回了无效响应。"
        case .apiError(let message):
            "Uniswap API 调用失败：\(message)"
        }
    }
}
