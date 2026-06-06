import Foundation

struct IntentClassifierPrompt {
    var systemPrompt: String { Self.system }

    func buildUserPayload(
        selectedContext: String,
        previousIntent: WalletIntentDraft?,
        chainHint: String,
        question: String
    ) -> String {
        let truncated = Self.truncate(selectedContext, byteLimit: 800)
        var parts: [String] = []
        parts.append("[selected_context]\n\(truncated)")

        if let previousIntent {
            let priorJSON = Self.serializePreviousIntent(previousIntent)
            parts.append("[previous_intent]\n\(priorJSON)")
        }

        parts.append("[chain_hint]\n\(chainHint)")
        parts.append("[user_question]\n\(question)")
        return parts.joined(separator: "\n\n")
    }

    private static let system: String = """
    你是 ClipMind 的钱包意图分类器。把"用户选中文字 + 用户问句"翻译成结构化 JSON。

    只输出一个 JSON 对象，不要 markdown，不要解释，不要代码块。

    action 必须是下列之一：
    - transfer：用户想从本地钱包转出资产
    - swap：用户想用一种资产买另一种代币
    - check_balance：用户想查本地钱包余额
    - check_token：用户想查代币信息或风险
    - check_tx：用户想查某笔交易做了什么
    - check_address：用户想查某个钱包地址的资产或风险
    - ask：其他问题（包括解释概念、追问、不涉及钱包操作）
    - unsupported：识别到钱包操作但 ClipMind 不支持（跨链、staking、NFT 操作、限价单等）

    chain 必须是下列之一或 null：
    ethereum / base / arbitrum / optimism / polygon / unichain

    [chain_hint] 解释：
    - 如果 chain_hint 是上面六链之一，表示用户已显式选定，输出 chain 优先用该值。
    - 如果 chain_hint 是 "auto"，表示用户没有指定链，请根据 target_address 的实际部署链推断 chain（例如 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 是 Ethereum 主网的 USDC，chain 应该是 ethereum；0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 是 Base USDC，chain 应该是 base）。不要把 chain_hint 的 "auto" 写进输出。
    - 如果完全无法判断链，chain 填 null。

    字段规则：
    - target_address：0x + 40 位十六进制；否则填 ""
    - transaction_hash：0x + 64 位十六进制；否则填 ""
    - spend_asset_symbol：只能是 "USDC" 或 "ETH"；"5u" 或 "20U" 等同 USDC；其他一律 ""
    - spend_amount：十进制字符串，不含单位
    - slippage_percent：数字或 null
    - 任何无关字段一律填 "" 或 null，不要省略

    如果 [previous_intent] 存在，合并补字段或字段变更，输出完整对象。

    [examples]
    selected_context: 0x2222222222222222222222222222222222222222
    user_question: 给这个地址转 5 USDC
    => {"action":"transfer","chain":"base","target_address":"0x2222222222222222222222222222222222222222","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}

    selected_context: doge
    user_question: 我想买 5u 这个代币
    => {"action":"swap","chain":null,"target_address":"","target_query":"doge","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}

    selected_context: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
    user_question: 用 0.1 ETH 买这个
    => {"action":"swap","chain":"base","target_address":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","target_query":"","transaction_hash":"","spend_asset_symbol":"ETH","spend_amount":"0.1","slippage_percent":null,"unsupported_reason":""}

    selected_context: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    user_question: 这个地址安全吗
    => {"action":"check_address","chain":"ethereum","target_address":"0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}

    selected_context: 0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789
    user_question: 这笔交易做了什么
    => {"action":"check_tx","chain":null,"target_address":"","target_query":"","transaction_hash":"0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}

    selected_context: Aave
    user_question: 这个项目可以质押吗
    => {"action":"unsupported","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":"Staking 暂未支持"}
    """

    private static func truncate(_ value: String, byteLimit: Int) -> String {
        let utf8 = Array(value.utf8)
        guard utf8.count > byteLimit else { return value }
        var cutoff = byteLimit
        while cutoff > 0, (utf8[cutoff] & 0xC0) == 0x80 {
            cutoff -= 1
        }
        let head = String(decoding: utf8.prefix(cutoff), as: UTF8.self)
        return head + "\n…（已按字节截断）"
    }

    private static func serializePreviousIntent(_ draft: WalletIntentDraft) -> String {
        let assetSymbol: String
        switch draft.spendAsset.symbol.uppercased() {
        case "USDC": assetSymbol = "USDC"
        case "ETH": assetSymbol = "ETH"
        default: assetSymbol = ""
        }
        let actionRaw: String
        switch draft.action {
        case .ask: actionRaw = "ask"
        case .transfer: actionRaw = "transfer"
        case .swap: actionRaw = "swap"
        case .unsupported: actionRaw = "unsupported"
        }
        let slippageValue: Any = draft.slippage == 0 ? NSNull() : draft.slippage
        let payload: [String: Any] = [
            "action": actionRaw,
            "chain": draft.chain.id,
            "target_address": draft.targetAddress,
            "target_query": draft.targetQuery,
            "transaction_hash": "",
            "spend_asset_symbol": assetSymbol,
            "spend_amount": draft.spendAmount,
            "slippage_percent": slippageValue,
            "unsupported_reason": ""
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
