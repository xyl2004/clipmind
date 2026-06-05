# LLM Structured Intent Classifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the regex-based `WalletIntentParser` with an LLM-primary intent classifier (rules as fallback). Add 4 new read-only `check_*` action types and dispatch them to existing services. Ship behind `CLIPMIND_INTENT_BACKEND` env flag.

**Architecture:** Add `StructuredIntent` (LLM wire schema) + `IntentClassifier` (wraps a `IntentClassifierBackend` protocol) + `IntentClassifierPrompt` (static prompt assets). `LLMClient` gets a `classifyChat(system:user:)` method that the production backend uses. `AppStore.handleWalletIntentIfNeeded` calls the classifier first, degrades to `WalletIntentParser` on any failure, and dispatches all 8 actions (4 existing + 4 new). LLM only does NLU; App computes `missing_fields / risk_notes / confirmation_summary`.

**Tech Stack:** Swift 5.9, SwiftPM, no XCTest. Tests live in `Sources/AgentWallet/Support/CoreSelfTests.swift` and run via `swift run ClipMind --self-test-core` (driven by `script/test.sh`).

**Spec:** `docs/superpowers/specs/2026-06-05-llm-structured-intent-design.md`

---

## File Structure

**Create**
- `Sources/AgentWallet/Models/StructuredIntent.swift` — LLM wire types, decoder, adapter to `WalletIntentDraft`
- `Sources/AgentWallet/Services/IntentClassifier.swift` — `IntentClassifierBackend` protocol, `IntentClassifier` struct with retry logic, error types
- `Sources/AgentWallet/Support/IntentClassifierPrompt.swift` — system prompt + few-shot + user payload builder

**Modify**
- `Sources/AgentWallet/Services/LLMClient.swift` — add `classifyChat(system:user:) async throws -> String` method
- `Sources/AgentWallet/Stores/AppStore.swift` — inject `IntentClassifier`, read env flag, rewrite `handleWalletIntentIfNeeded`, add `check_*` and `unsupported` dispatch
- `Sources/AgentWallet/Support/CoreSelfTests.swift` — add 4 new test functions; wire into `run()`

**Untouched**
- `Sources/AgentWallet/Models/WalletIntent.swift` — `WalletIntentParser` remains intact as fallback

---

## Task 1: Create `StructuredIntent` type with 8 actions

**Files:**
- Create: `Sources/AgentWallet/Models/StructuredIntent.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift:1-20` (add test wire-up)

- [ ] **Step 1: Write failing test**

Add this function to `CoreSelfTests.swift` (place after `testWalletIntentParser`):

```swift
private static func testStructuredIntentTypes(_ suite: inout CoreSelfTestSuite) throws {
    let transfer = StructuredIntent(
        action: .transfer,
        chain: "base",
        targetAddress: "0x2222222222222222222222222222222222222222",
        targetQuery: "",
        transactionHash: "",
        spendAssetSymbol: "USDC",
        spendAmount: "5",
        slippagePercent: nil,
        unsupportedReason: ""
    )
    try suite.equal(transfer.action, StructuredIntentAction.transfer, "structured intent transfer action")
    try suite.equal(transfer.chain, "base", "structured intent chain id")

    let ask = StructuredIntent.empty(action: .ask)
    try suite.equal(ask.action, StructuredIntentAction.ask, "structured intent ask via empty()")
    try suite.equal(ask.chain, nil, "structured intent ask has nil chain")
    try suite.equal(ask.targetAddress, "", "structured intent ask empty target_address")

    let allCases = StructuredIntentAction.allCases.map(\.rawValue).sorted()
    try suite.equal(
        allCases,
        ["ask", "check_address", "check_balance", "check_token", "check_tx", "swap", "transfer", "unsupported"].sorted(),
        "structured intent action vocabulary is exactly 8 values"
    )
}
```

Wire it into `CoreSelfTests.run()`:

```swift
static func run() async throws -> String {
    var suite = CoreSelfTestSuite()
    try testWalletIntentParser(&suite)
    try testStructuredIntentTypes(&suite)    // NEW
    try testTransferPlanBuilder(&suite)
    // ... rest unchanged
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: build fails with `cannot find 'StructuredIntent' in scope`.

- [ ] **Step 3: Implement `StructuredIntent` type**

Create `Sources/AgentWallet/Models/StructuredIntent.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS with `pass: structured intent transfer action`, etc.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Models/StructuredIntent.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Add StructuredIntent value type for LLM intent wire schema

Defines the 8-action vocabulary (ask/transfer/swap/unsupported plus
the four read-only check_* actions) and the 9 fields that the LLM
classifier will output. No decoding or adapter logic yet.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Decode `StructuredIntent` from JSON

**Files:**
- Modify: `Sources/AgentWallet/Models/StructuredIntent.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add to `testStructuredIntentTypes` (after the `allCases` assertion):

```swift
    let validTransferJSON = """
    {"action":"transfer","chain":"base","target_address":"0x2222222222222222222222222222222222222222","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
    """
    let decodedTransfer = try StructuredIntent.decode(raw: validTransferJSON)
    try suite.equal(decodedTransfer.action, StructuredIntentAction.transfer, "decode transfer action")
    try suite.equal(decodedTransfer.targetAddress, "0x2222222222222222222222222222222222222222", "decode transfer target_address")
    try suite.equal(decodedTransfer.spendAmount, "5", "decode transfer spend_amount")
    try suite.equal(decodedTransfer.slippagePercent, nil, "decode transfer null slippage")

    let validSwapJSON = """
    {"action":"swap","chain":null,"target_address":"","target_query":"doge","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":1.0,"unsupported_reason":""}
    """
    let decodedSwap = try StructuredIntent.decode(raw: validSwapJSON)
    try suite.equal(decodedSwap.action, StructuredIntentAction.swap, "decode swap action")
    try suite.equal(decodedSwap.chain, nil, "decode swap null chain")
    try suite.equal(decodedSwap.targetQuery, "doge", "decode swap target_query")
    try suite.equal(decodedSwap.slippagePercent, 1.0, "decode swap slippage 1.0")

    let validCheckTxJSON = """
    {"action":"check_tx","chain":"ethereum","target_address":"","target_query":"","transaction_hash":"0xabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
    """
    let decodedCheckTx = try StructuredIntent.decode(raw: validCheckTxJSON)
    try suite.equal(decodedCheckTx.action, StructuredIntentAction.checkTx, "decode check_tx action")
    try suite.equal(decodedCheckTx.transactionHash.count, 66, "decode check_tx hash length")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: build fails with `value of type 'StructuredIntent.Type' has no member 'decode'`.

- [ ] **Step 3: Implement decoder**

Append to `Sources/AgentWallet/Models/StructuredIntent.swift`:

```swift
enum StructuredIntentDecodeError: LocalizedError, Equatable {
    case invalidJSON(String)
    case missingField(String)
    case invalidAction(String)
    case invalidAddress(String)
    case invalidTransactionHash(String)
    case invalidChain(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "intent JSON unparseable: \(detail)"
        case .missingField(let name):
            return "intent JSON missing field: \(name)"
        case .invalidAction(let raw):
            return "intent action not in vocabulary: \(raw)"
        case .invalidAddress(let raw):
            return "intent target_address not 0x+40 hex: \(raw)"
        case .invalidTransactionHash(let raw):
            return "intent transaction_hash not 0x+64 hex: \(raw)"
        case .invalidChain(let raw):
            return "intent chain not in supported list: \(raw)"
        }
    }
}

extension StructuredIntent {
    private static let allowedChainIDs: Set<String> = Set(ChainRegistry.supported.map(\.id))

    static func decode(raw: String) throws -> StructuredIntent {
        let payload = raw.data(using: .utf8) ?? Data()
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])
        } catch {
            throw StructuredIntentDecodeError.invalidJSON(error.localizedDescription)
        }

        guard let object = parsed as? [String: Any] else {
            throw StructuredIntentDecodeError.invalidJSON("top level not object")
        }

        guard let actionRaw = object["action"] as? String else {
            throw StructuredIntentDecodeError.missingField("action")
        }
        guard let action = StructuredIntentAction(rawValue: actionRaw) else {
            throw StructuredIntentDecodeError.invalidAction(actionRaw)
        }

        let chain: String?
        if let chainRaw = object["chain"] as? String, !chainRaw.isEmpty {
            guard allowedChainIDs.contains(chainRaw) else {
                throw StructuredIntentDecodeError.invalidChain(chainRaw)
            }
            chain = chainRaw
        } else {
            chain = nil
        }

        let targetAddress = (object["target_address"] as? String) ?? ""
        if !targetAddress.isEmpty, !QueryClassifier.isAddress(targetAddress) {
            throw StructuredIntentDecodeError.invalidAddress(targetAddress)
        }

        let transactionHash = (object["transaction_hash"] as? String) ?? ""
        if !transactionHash.isEmpty, !QueryClassifier.isTransactionHash(transactionHash) {
            throw StructuredIntentDecodeError.invalidTransactionHash(transactionHash)
        }

        let targetQuery = (object["target_query"] as? String) ?? ""
        let spendAssetSymbol = (object["spend_asset_symbol"] as? String) ?? ""
        let spendAmount = (object["spend_amount"] as? String) ?? ""
        let unsupportedReason = (object["unsupported_reason"] as? String) ?? ""

        let slippagePercent: Double?
        switch object["slippage_percent"] {
        case let value as Double:
            slippagePercent = value
        case let value as Int:
            slippagePercent = Double(value)
        case let value as NSNumber:
            slippagePercent = value.doubleValue
        default:
            slippagePercent = nil
        }

        return StructuredIntent(
            action: action,
            chain: chain,
            targetAddress: targetAddress,
            targetQuery: targetQuery,
            transactionHash: transactionHash,
            spendAssetSymbol: spendAssetSymbol,
            spendAmount: spendAmount,
            slippagePercent: slippagePercent,
            unsupportedReason: unsupportedReason
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS with `pass: decode transfer action`, etc.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Models/StructuredIntent.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Add StructuredIntent.decode strict JSON decoder

Decodes the 9-field intent schema from a raw JSON string and enforces
the action vocabulary, the chain whitelist, and the address/hash hex
shape. Coerces missing fields to empty defaults. No tolerance for
markdown wrapping yet.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Tolerant JSON decode (markdown stripping + trailing text)

**Files:**
- Modify: `Sources/AgentWallet/Models/StructuredIntent.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Append to `testStructuredIntentTypes`:

```swift
    let wrapped = """
    Sure, here is the JSON:
    ```json
    {"action":"ask","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
    ```
    Hope this helps.
    """
    let decodedWrapped = try StructuredIntent.decode(raw: wrapped)
    try suite.equal(decodedWrapped.action, StructuredIntentAction.ask, "decode strips markdown wrapper")

    let trailingText = """
    {"action":"unsupported","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":"Bridge 暂未支持"}
    用户希望跨链。
    """
    let decodedTrailing = try StructuredIntent.decode(raw: trailingText)
    try suite.equal(decodedTrailing.action, StructuredIntentAction.unsupported, "decode strips trailing prose")
    try suite.equal(decodedTrailing.unsupportedReason, "Bridge 暂未支持", "decode keeps unsupported_reason")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: `pass: decode transfer action` ... then failure at "decode strips markdown wrapper" because `JSONSerialization` won't parse the wrapped content.

- [ ] **Step 3: Add tolerant pre-parse**

In `Sources/AgentWallet/Models/StructuredIntent.swift`, replace the body of `decode(raw:)` so it runs the raw string through an extractor first. Add this helper to the same file:

```swift
extension StructuredIntent {
    static func extractFirstJSONObject(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ```json ... ``` or ``` ... ``` fences first.
        var working = trimmed
        if let fenceStart = working.range(of: "```") {
            let afterFence = working[fenceStart.upperBound...]
            let prefixSkipped: Substring
            if let newline = afterFence.firstIndex(of: "\n") {
                prefixSkipped = afterFence[afterFence.index(after: newline)...]
            } else {
                prefixSkipped = afterFence
            }
            if let fenceEnd = prefixSkipped.range(of: "```") {
                working = String(prefixSkipped[..<fenceEnd.lowerBound])
            } else {
                working = String(prefixSkipped)
            }
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Slice from the first '{' to the matching '}'.
        guard let start = working.firstIndex(of: "{") else {
            return working
        }
        var depth = 0
        var endIndex: String.Index?
        var index = start
        while index < working.endIndex {
            let character = working[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = working.index(after: index)
                    break
                }
            }
            index = working.index(after: index)
        }

        guard let end = endIndex else {
            return String(working[start...])
        }
        return String(working[start..<end])
    }
}
```

Then change the top of `decode(raw:)`:

```swift
static func decode(raw: String) throws -> StructuredIntent {
    let cleaned = extractFirstJSONObject(from: raw)
    let payload = cleaned.data(using: .utf8) ?? Data()
    // ... rest unchanged
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS for both wrapped and trailing-text cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Models/StructuredIntent.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Tolerate markdown-wrapped JSON in StructuredIntent.decode

deepseek-v4-flash sometimes returns the JSON inside ```json ... ```
fences or with trailing Chinese prose. Strip fences, then slice from
the first { to its matching } before handing to JSONSerialization.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Reject invalid `StructuredIntent` payloads

**Files:**
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Append to `testStructuredIntentTypes`:

```swift
    try suite.expectThrows("decode rejects unknown action") {
        _ = try StructuredIntent.decode(raw: """
        {"action":"buy_nft","chain":"base","target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        """)
    }

    try suite.expectThrows("decode rejects bad target_address hex") {
        _ = try StructuredIntent.decode(raw: """
        {"action":"transfer","chain":"base","target_address":"0xnotvalid","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
        """)
    }

    try suite.expectThrows("decode rejects bad transaction_hash") {
        _ = try StructuredIntent.decode(raw: """
        {"action":"check_tx","chain":"base","target_address":"","target_query":"","transaction_hash":"0xtoolittle","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        """)
    }

    try suite.expectThrows("decode rejects unknown chain") {
        _ = try StructuredIntent.decode(raw: """
        {"action":"swap","chain":"solana","target_address":"","target_query":"doge","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
        """)
    }

    try suite.expectThrows("decode rejects truly broken JSON") {
        _ = try StructuredIntent.decode(raw: "not json at all")
    }
```

- [ ] **Step 2: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS — these throw paths are already implemented in Task 2. This test just locks the contract in.

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Lock StructuredIntent.decode rejection contract in tests

Asserts that unknown actions, malformed addresses/hashes, unknown chain
ids, and unparseable JSON all throw StructuredIntentDecodeError so the
retry-then-fallback path stays predictable.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Adapter — `StructuredIntent` → `WalletIntentDraft?`

**Files:**
- Modify: `Sources/AgentWallet/Models/StructuredIntent.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add this new test function in `CoreSelfTests.swift` (placement: after `testStructuredIntentTypes`):

```swift
private static func testStructuredIntentAdapter(_ suite: inout CoreSelfTestSuite) throws {
    let transferIntent = StructuredIntent(
        action: .transfer,
        chain: "base",
        targetAddress: "0x2222222222222222222222222222222222222222",
        targetQuery: "",
        transactionHash: "",
        spendAssetSymbol: "USDC",
        spendAmount: "5",
        slippagePercent: nil,
        unsupportedReason: ""
    )
    let transferDraft = transferIntent.toWalletIntentDraft(selectedContext: "0x2222222222222222222222222222222222222222", fallbackChain: ChainRegistry.base)
    try suite.equal(transferDraft?.action, WalletIntentAction.transfer, "adapter transfer action")
    try suite.equal(transferDraft?.recipientAddress, "0x2222222222222222222222222222222222222222", "adapter transfer recipient")
    try suite.equal(transferDraft?.spendAmount, "5", "adapter transfer amount")
    try suite.equal(transferDraft?.spendAsset.symbol, "USDC", "adapter transfer asset")
    try suite.equal(transferDraft?.chain.id, "base", "adapter transfer chain follows intent")
    try suite.check(transferDraft?.isComplete == true, "adapter transfer complete")

    let swapIntent = StructuredIntent(
        action: .swap,
        chain: nil,
        targetAddress: "",
        targetQuery: "doge",
        transactionHash: "",
        spendAssetSymbol: "USDC",
        spendAmount: "5",
        slippagePercent: 1.0,
        unsupportedReason: ""
    )
    let swapDraft = swapIntent.toWalletIntentDraft(selectedContext: "doge", fallbackChain: ChainRegistry.base)
    try suite.equal(swapDraft?.action, WalletIntentAction.swap, "adapter swap action")
    try suite.equal(swapDraft?.targetQuery, "doge", "adapter swap target_query")
    try suite.equal(swapDraft?.targetAddress, "", "adapter swap no premature address")
    try suite.equal(swapDraft?.chain.id, "base", "adapter swap chain falls back when null")
    try suite.equal(swapDraft?.slippage, 1.0, "adapter swap slippage explicit")

    let swapMissingAmount = StructuredIntent(
        action: .swap,
        chain: "base",
        targetAddress: "",
        targetQuery: "doge",
        transactionHash: "",
        spendAssetSymbol: "USDC",
        spendAmount: "",
        slippagePercent: nil,
        unsupportedReason: ""
    )
    let missingDraft = swapMissingAmount.toWalletIntentDraft(selectedContext: "doge", fallbackChain: ChainRegistry.base)
    try suite.check(missingDraft?.missingFields.contains("支付金额") == true, "adapter recomputes missing amount")

    let ask = StructuredIntent.empty(action: .ask)
    try suite.equal(
        ask.toWalletIntentDraft(selectedContext: "Uniswap", fallbackChain: ChainRegistry.base) == nil,
        true,
        "adapter returns nil for ask"
    )
    for action in [StructuredIntentAction.checkBalance, .checkToken, .checkTx, .checkAddress, .unsupported] {
        try suite.equal(
            StructuredIntent.empty(action: action)
                .toWalletIntentDraft(selectedContext: "", fallbackChain: ChainRegistry.base) == nil,
            true,
            "adapter returns nil for \(action.rawValue)"
        )
    }
}
```

Wire it into `run()`:

```swift
try testStructuredIntentTypes(&suite)
try testStructuredIntentAdapter(&suite)    // NEW
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: build fails with `value of type 'StructuredIntent' has no member 'toWalletIntentDraft'`.

- [ ] **Step 3: Implement adapter**

Append to `Sources/AgentWallet/Models/StructuredIntent.swift`:

```swift
extension StructuredIntent {
    /// Convert to a WalletIntentDraft consumable by the existing transfer/swap
    /// flows. Returns nil for actions that don't need a draft (ask, check_*,
    /// unsupported) — those are dispatched directly by AppStore.
    func toWalletIntentDraft(
        selectedContext: String,
        fallbackChain: ChainProfile
    ) -> WalletIntentDraft? {
        switch action {
        case .transfer:
            let chain = ChainRegistry.profile(for: chain ?? "") ?? fallbackChain
            let asset = resolveSpendAsset(chain: chain, defaultForSwap: false)
            let recipient = targetAddress
            var missing: [String] = []
            if recipient.isEmpty { missing.append("收款地址") }
            if spendAmount.isEmpty { missing.append("转账金额") }
            if asset == nil { missing.append("转账资产") }
            let resolvedAsset = asset ?? chain.defaultSpendToken
            return WalletIntentDraft(
                action: .transfer,
                selectedContext: selectedContext,
                targetAddress: recipient,
                targetQuery: "",
                chain: chain,
                spendAsset: resolvedAsset,
                spendAmount: spendAmount,
                recipientAddress: recipient,
                slippage: 0,
                missingFields: missing,
                riskNotes: [
                    "AI 只生成计划,不会签名或广播。",
                    "请确认收款地址不可撤销。",
                    "签名前需要输入收款地址后 4 位。"
                ],
                confirmationSummary: missing.isEmpty
                    ? "准备在 \(chain.displayName) 向 \(JSONPrettyPrinter.shortAddress(recipient)) 转账 \(spendAmount) \(resolvedAsset.symbol)。"
                    : "转账计划缺少:\(missing.joined(separator: "、"))。"
            )

        case .swap:
            let chain = ChainRegistry.profile(for: chain ?? "") ?? fallbackChain
            let asset = resolveSpendAsset(chain: chain, defaultForSwap: true)
            var missing: [String] = []
            if targetAddress.isEmpty && targetQuery.isEmpty { missing.append("目标代币地址或名称") }
            if spendAmount.isEmpty { missing.append("支付金额") }
            if asset == nil { missing.append("支付资产") }
            let resolvedAsset = asset ?? chain.defaultSpendToken
            let slippage = slippagePercent ?? 1.0
            let displayTarget: String
            if !targetAddress.isEmpty {
                displayTarget = JSONPrettyPrinter.shortAddress(targetAddress)
            } else if !targetQuery.isEmpty {
                displayTarget = "\(targetQuery)(待确认合约)"
            } else {
                displayTarget = "待补充代币"
            }
            return WalletIntentDraft(
                action: .swap,
                selectedContext: selectedContext,
                targetAddress: targetAddress,
                targetQuery: targetQuery,
                chain: chain,
                spendAsset: resolvedAsset,
                spendAmount: spendAmount,
                recipientAddress: "",
                slippage: slippage,
                missingFields: missing,
                riskNotes: [
                    "AI 只生成计划,不会签名或广播。",
                    "Uniswap 报价过期后必须重新生成。",
                    "签名前需要核对目标代币合约和支付金额。"
                ],
                confirmationSummary: "准备在 \(chain.displayName) 用 \(spendAmount.isEmpty ? "待补充" : spendAmount) \(resolvedAsset.symbol) 购买 \(displayTarget)。"
            )

        case .ask, .unsupported, .checkBalance, .checkToken, .checkTx, .checkAddress:
            return nil
        }
    }

    private func resolveSpendAsset(chain: ChainProfile, defaultForSwap: Bool) -> TokenProfile? {
        let normalized = spendAssetSymbol.uppercased()
        if normalized == "ETH" { return .nativeETH }
        if normalized == "USDC" {
            if chain.defaultSpendToken.symbol.uppercased() == "USDC" {
                return chain.defaultSpendToken
            }
            return nil
        }
        if normalized.isEmpty {
            return defaultForSwap ? chain.defaultSpendToken : nil
        }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS for all adapter cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Models/StructuredIntent.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Adapt StructuredIntent to WalletIntentDraft for transfer and swap

App recomputes missing_fields, risk_notes, and confirmation_summary
from typed fields instead of trusting the LLM, so risk text can't be
hallucinated. ask/check_*/unsupported return nil — AppStore will
dispatch them through their own paths next.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Build `IntentClassifier` with `IntentClassifierBackend` protocol and Stub

**Files:**
- Create: `Sources/AgentWallet/Services/IntentClassifier.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add this new test function in `CoreSelfTests.swift`:

```swift
private static func testIntentClassifierStub(_ suite: inout CoreSelfTestSuite) async throws {
    let goodJSON = """
    {"action":"transfer","chain":"base","target_address":"0x2222222222222222222222222222222222222222","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
    """
    let stub = StubIntentClassifierBackend(responses: [.success(goodJSON)])
    let classifier = IntentClassifier(backend: stub)

    let result = try await classifier.classify(
        selectedContext: "0x2222222222222222222222222222222222222222",
        previousIntent: nil,
        chainHint: "base",
        question: "给这个地址转 5 USDC"
    )
    try suite.equal(result.action, StructuredIntentAction.transfer, "classifier returns parsed intent")
    try suite.equal(stub.callCount, 1, "classifier called backend exactly once on happy path")
}
```

Wire it in:

```swift
try testStructuredIntentAdapter(&suite)
try await testIntentClassifierStub(&suite)    // NEW (note: async)
```

Also change `try testStructuredIntentAdapter` placement so `await` ordering compiles — since `run()` is already `async throws`, adding an awaited call is fine.

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: build fails with `cannot find type 'IntentClassifier' in scope` and `cannot find 'StubIntentClassifierBackend'`.

- [ ] **Step 3: Implement classifier + protocol + stub**

Create `Sources/AgentWallet/Services/IntentClassifier.swift`:

```swift
import Foundation

protocol IntentClassifierBackend {
    /// Send one chat completion with the given system + user prompt.
    /// Returns the assistant message's raw content (may include markdown wrap).
    func classifyChat(system: String, user: String) async throws -> String
}

enum IntentClassifierError: LocalizedError {
    case retryExhausted(String)

    var errorDescription: String? {
        switch self {
        case .retryExhausted(let reason):
            return "意图分类器重试仍失败:\(reason)"
        }
    }
}

struct IntentClassifier {
    let backend: IntentClassifierBackend
    let prompt: IntentClassifierPrompt

    init(backend: IntentClassifierBackend, prompt: IntentClassifierPrompt = IntentClassifierPrompt()) {
        self.backend = backend
        self.prompt = prompt
    }

    func classify(
        selectedContext: String,
        previousIntent: WalletIntentDraft?,
        chainHint: String,
        question: String
    ) async throws -> StructuredIntent {
        let user = prompt.buildUserPayload(
            selectedContext: selectedContext,
            previousIntent: previousIntent,
            chainHint: chainHint,
            question: question
        )
        return try await classifyWithRetry(system: prompt.systemPrompt, user: user, retriesLeft: 1)
    }

    private func classifyWithRetry(
        system: String,
        user: String,
        retriesLeft: Int
    ) async throws -> StructuredIntent {
        let raw = try await backend.classifyChat(system: system, user: user)
        do {
            return try StructuredIntent.decode(raw: raw)
        } catch let decodeError as StructuredIntentDecodeError {
            guard retriesLeft > 0 else {
                throw IntentClassifierError.retryExhausted(decodeError.localizedDescription)
            }
            let retryUser = user + "\n\nYour previous output was rejected: \(decodeError.localizedDescription). Output ONLY a single JSON object matching the schema."
            return try await classifyWithRetry(system: system, user: retryUser, retriesLeft: retriesLeft - 1)
        }
    }
}

/// Test-only fake backend that returns canned responses in order.
/// Each call pops the head of `responses`. If empty, throws `noMoreResponses`.
final class StubIntentClassifierBackend: IntentClassifierBackend {
    enum CannedResponse {
        case success(String)
        case failure(Error)
    }

    enum StubError: Error {
        case noMoreResponses
    }

    private(set) var callCount: Int = 0
    private(set) var lastSystem: String = ""
    private(set) var lastUsers: [String] = []
    private var responses: [CannedResponse]

    init(responses: [CannedResponse]) {
        self.responses = responses
    }

    func classifyChat(system: String, user: String) async throws -> String {
        callCount += 1
        lastSystem = system
        lastUsers.append(user)
        guard !responses.isEmpty else {
            throw StubError.noMoreResponses
        }
        let head = responses.removeFirst()
        switch head {
        case .success(let raw):
            return raw
        case .failure(let error):
            throw error
        }
    }
}
```

This file refers to `IntentClassifierPrompt`. Add a minimal stub for it that we'll flesh out in Task 9:

```swift
// Placeholder so this task compiles. Full content lands in Task 9.
struct IntentClassifierPrompt {
    var systemPrompt: String { "" }
    func buildUserPayload(
        selectedContext: String,
        previousIntent: WalletIntentDraft?,
        chainHint: String,
        question: String
    ) -> String {
        return ""
    }
}
```

Put `IntentClassifierPrompt` at the end of `IntentClassifier.swift` for now; it'll move to its own file in Task 9.

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS for `classifier returns parsed intent`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Services/IntentClassifier.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Add IntentClassifier with protocol-based backend and stub

IntentClassifierBackend is a one-method protocol so production code
plugs LLMClient in while tests inject canned JSON strings. The
classifier itself owns retry-on-decode-error logic. Prompt assets
are a placeholder until Task 9.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Retry once when the LLM returns bad JSON

**Files:**
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Append to `testIntentClassifierStub`:

```swift
    let badThenGood = StubIntentClassifierBackend(responses: [
        .success("not json at all"),
        .success("""
        {"action":"swap","chain":"base","target_address":"","target_query":"doge","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":1.0,"unsupported_reason":""}
        """)
    ])
    let retryClassifier = IntentClassifier(backend: badThenGood)
    let retried = try await retryClassifier.classify(
        selectedContext: "doge",
        previousIntent: nil,
        chainHint: "base",
        question: "我想买 5u 这个代币"
    )
    try suite.equal(retried.action, StructuredIntentAction.swap, "classifier retries once on bad JSON")
    try suite.equal(badThenGood.callCount, 2, "classifier called backend twice on retry path")
    try suite.check(
        badThenGood.lastUsers.last?.contains("Your previous output was rejected") == true,
        "retry payload includes rejection feedback"
    )
```

- [ ] **Step 2: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS — retry logic was implemented in Task 6. This test pins the contract.

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Test IntentClassifier retries once with rejection feedback

Locks the contract that the second call adds a "Your previous output
was rejected" line so the LLM has a clear signal to correct itself.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Give up after the single retry

**Files:**
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Append to `testIntentClassifierStub`:

```swift
    let alwaysBad = StubIntentClassifierBackend(responses: [
        .success("not json"),
        .success("still not json")
    ])
    let exhaustClassifier = IntentClassifier(backend: alwaysBad)
    var thrown: Error?
    do {
        _ = try await exhaustClassifier.classify(
            selectedContext: "anything",
            previousIntent: nil,
            chainHint: "base",
            question: "?"
        )
    } catch {
        thrown = error
    }
    try suite.check(thrown is IntentClassifierError, "classifier throws IntentClassifierError after retry exhausted")
    try suite.equal(alwaysBad.callCount, 2, "classifier stops at one retry (two calls total)")
```

- [ ] **Step 2: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS — implementation is already in place from Task 6.

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Test IntentClassifier gives up after one retry

Asserts the retry budget is exactly one (two total calls) and that the
final error type is IntentClassifierError so AppStore can branch on it
to fall back to the rule parser.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Real `IntentClassifierPrompt` (system prompt + few-shot + payload builder)

**Files:**
- Create: `Sources/AgentWallet/Support/IntentClassifierPrompt.swift`
- Modify: `Sources/AgentWallet/Services/IntentClassifier.swift` (remove the placeholder)
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add this new test function:

```swift
private static func testIntentClassifierPrompt(_ suite: inout CoreSelfTestSuite) throws {
    let prompt = IntentClassifierPrompt()
    try suite.check(prompt.systemPrompt.contains("check_balance"), "system prompt lists check_balance")
    try suite.check(prompt.systemPrompt.contains("check_address"), "system prompt lists check_address")
    try suite.check(prompt.systemPrompt.contains("unichain"), "system prompt lists unichain")
    try suite.check(prompt.systemPrompt.contains("ethereum"), "system prompt lists ethereum")

    let firstTurn = prompt.buildUserPayload(
        selectedContext: "doge",
        previousIntent: nil,
        chainHint: "base",
        question: "我想买 5u 这个代币"
    )
    try suite.check(firstTurn.contains("[selected_context]"), "user payload includes selected_context block")
    try suite.check(firstTurn.contains("[user_question]"), "user payload includes user_question block")
    try suite.check(!firstTurn.contains("[previous_intent]"), "first turn omits previous_intent block entirely")

    let priorDraft = WalletIntentParser.parse(
        selectedText: "doge",
        question: "我想买这个币",
        chain: ChainRegistry.base
    )
    let secondTurn = prompt.buildUserPayload(
        selectedContext: "doge",
        previousIntent: priorDraft,
        chainHint: "base",
        question: "5u"
    )
    try suite.check(secondTurn.contains("[previous_intent]"), "continuation turn includes previous_intent block")
    try suite.check(secondTurn.contains("\"action\":\"swap\""), "previous_intent block serializes prior action")

    let longContext = String(repeating: "中", count: 2000)
    let truncated = prompt.buildUserPayload(
        selectedContext: longContext,
        previousIntent: nil,
        chainHint: "base",
        question: "?"
    )
    try suite.check(truncated.count < longContext.count, "user payload truncates oversized selected context")
}
```

Wire it in:

```swift
try await testIntentClassifierStub(&suite)
try testIntentClassifierPrompt(&suite)    // NEW
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: fails on first assertion because the placeholder `systemPrompt` is empty.

- [ ] **Step 3: Implement `IntentClassifierPrompt`**

Create `Sources/AgentWallet/Support/IntentClassifierPrompt.swift`:

```swift
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

    只输出一个 JSON 对象,不要 markdown,不要解释,不要代码块。

    action 必须是下列之一:
    - transfer:用户想从本地钱包转出资产
    - swap:用户想用一种资产买另一种代币
    - check_balance:用户想查本地钱包余额
    - check_token:用户想查代币信息或风险
    - check_tx:用户想查某笔交易做了什么
    - check_address:用户想查某个钱包地址的资产或风险
    - ask:其他问题(包括解释概念、追问、不涉及钱包操作)
    - unsupported:识别到钱包操作但 ClipMind 不支持(跨链、staking、NFT 操作、限价单等)

    chain 必须是下列之一或 null:
    ethereum / base / arbitrum / optimism / polygon / unichain

    字段规则:
    - target_address:0x + 40 位十六进制;否则填 ""
    - transaction_hash:0x + 64 位十六进制;否则填 ""
    - spend_asset_symbol:只能是 "USDC" 或 "ETH";"5u" 或 "20U" 等同 USDC;其他一律 ""
    - spend_amount:十进制字符串,不含单位
    - slippage_percent:数字或 null
    - 任何无关字段一律填 "" 或 null,不要省略

    如果 [previous_intent] 存在,合并补字段或字段变更,输出完整对象。

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
        return head + "\n…(已按字节截断)"
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
        let payload: [String: Any] = [
            "action": actionRaw,
            "chain": draft.chain.id,
            "target_address": draft.targetAddress,
            "target_query": draft.targetQuery,
            "transaction_hash": "",
            "spend_asset_symbol": assetSymbol,
            "spend_amount": draft.spendAmount,
            "slippage_percent": draft.slippage as Any,
            "unsupported_reason": ""
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
```

Then remove the placeholder `IntentClassifierPrompt` struct at the bottom of `Sources/AgentWallet/Services/IntentClassifier.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS for all `testIntentClassifierPrompt` assertions.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Support/IntentClassifierPrompt.swift Sources/AgentWallet/Services/IntentClassifier.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Flesh out IntentClassifierPrompt with system + few-shot + payload

Six few-shot examples cover transfer / swap address / swap by name /
check_address / check_tx / unsupported. User payload omits the
previous_intent block on the first turn and truncates oversized
selected context to 800 bytes at a UTF-8 boundary.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `LLMClient.classifyChat` production backend

**Files:**
- Modify: `Sources/AgentWallet/Services/LLMClient.swift`

This task has no unit test — `LLMClient` makes real HTTP. It's exercised via build verification at Task 15.

- [ ] **Step 1: Add `classifyChat` to `LLMClient`**

In `Sources/AgentWallet/Services/LLMClient.swift`, add the following method inside `struct LLMClient` (after `answerAboutContext`):

```swift
func classifyChat(system: String, user: String) async throws -> String {
    let messages: [[String: Any]] = [
        ["role": "system", "content": system],
        ["role": "user", "content": user]
    ]
    return try await sendChat(messages: messages, temperature: 0.0, maxTokens: 220)
}
```

- [ ] **Step 2: Make `LLMClient` conform to `IntentClassifierBackend`**

At the bottom of `Sources/AgentWallet/Services/LLMClient.swift`, add:

```swift
extension LLMClient: IntentClassifierBackend {}
```

- [ ] **Step 3: Build check**

Run: `swift build`
Expected: build succeeds. No new tests because the production HTTP call is integration territory; behavior is shaped by `IntentClassifier` tests via the stub.

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentWallet/Services/LLMClient.swift
git commit -m "$(cat <<'EOF'
Implement LLMClient.classifyChat as IntentClassifierBackend

Single chat completion with temperature 0 and 220-token cap, reusing
the existing sendChat plumbing for auth, endpoint resolution, and
error mapping.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Wire `IntentClassifier` into `AppStore`, read feature flag

**Files:**
- Modify: `Sources/AgentWallet/Stores/AppStore.swift`

- [ ] **Step 1: Add the field, init param, and flag reader**

In `AppStore`, locate the existing private fields block (`private let surfClient: SurfClient` etc.) and add:

```swift
private let intentClassifier: IntentClassifier
private let intentBackendMode: IntentBackendMode
```

Add an enum, place it near `IntentClassifier` callers at the top of the file (above `final class AppStore`):

```swift
enum IntentBackendMode: String {
    case auto
    case rule
    case llm

    static func fromEnvironment(_ env: [String: String]) -> IntentBackendMode {
        guard let raw = env["CLIPMIND_INTENT_BACKEND"]?.lowercased() else {
            return .auto
        }
        return IntentBackendMode(rawValue: raw) ?? .auto
    }

    var skipsLLM: Bool { self == .rule }
}
```

Then update the `init` of `AppStore`:

```swift
init(
    surfClient: SurfClient = SurfClient(),
    llmClient: LLMClient = LLMClient(),
    tradeProvider: UniswapTradeProvider = UniswapTradeProvider(),
    localWalletClient: LocalWalletClient = LocalWalletClient(),
    intentClassifier: IntentClassifier? = nil,
    intentBackendMode: IntentBackendMode? = nil
) {
    self.surfClient = surfClient
    self.llmClient = llmClient
    self.tradeProvider = tradeProvider
    self.localWalletClient = localWalletClient
    self.intentClassifier = intentClassifier ?? IntentClassifier(backend: llmClient)
    self.intentBackendMode = intentBackendMode ?? IntentBackendMode.fromEnvironment(ProcessInfo.processInfo.environment)

    do {
        localWalletAccount = try localWalletClient.loadAccount()
        if localWalletAccount != nil {
            Task { await refreshWalletBalance() }
        }
    } catch {
        walletStatusMessage = error.localizedDescription
    }
}
```

- [ ] **Step 2: Build check**

Run: `swift build`
Expected: build succeeds. No new self-test wiring yet — Task 12 exercises the flag.

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentWallet/Stores/AppStore.swift
git commit -m "$(cat <<'EOF'
Inject IntentClassifier and read CLIPMIND_INTENT_BACKEND flag

AppStore now holds an IntentClassifier (defaulted to LLMClient backend)
and an IntentBackendMode read once from the environment. No behavior
change yet — handleWalletIntentIfNeeded still uses WalletIntentParser.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: `handleWalletIntentIfNeeded` — LLM-first with rules fallback (transfer / swap / ask / unsupported)

**Files:**
- Modify: `Sources/AgentWallet/Stores/AppStore.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add this new test function in `CoreSelfTests.swift`:

```swift
@MainActor
private static func testAppStoreIntentDispatch(_ suite: inout CoreSelfTestSuite) async throws {
    let swapJSON = """
    {"action":"swap","chain":"base","target_address":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
    """
    let stub = StubIntentClassifierBackend(responses: [.success(swapJSON)])
    let store = AppStore(
        intentClassifier: IntentClassifier(backend: stub),
        intentBackendMode: .auto
    )
    store.input = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
    store.chatQuestion = "用 5u 买这个"
    await store.askAboutSelectedContext()

    try suite.equal(store.floatingWalletIntent?.action, WalletIntentAction.swap, "stub swap intent applied to store")
    try suite.equal(stub.callCount, 1, "store calls classifier once")

    // Fallback path: stub fails twice → AppStore uses WalletIntentParser
    let failingStub = StubIntentClassifierBackend(responses: [
        .success("not json"),
        .success("still not json")
    ])
    let store2 = AppStore(
        intentClassifier: IntentClassifier(backend: failingStub),
        intentBackendMode: .auto
    )
    store2.input = "0x2222222222222222222222222222222222222222"
    store2.chatQuestion = "给这个地址转 5 USDC"
    await store2.askAboutSelectedContext()
    try suite.equal(store2.floatingWalletIntent?.action, WalletIntentAction.transfer, "rules fallback produced transfer intent")
    try suite.equal(store2.floatingWalletIntent?.spendAmount, "5", "rules fallback parsed amount")

    // rule mode: never calls LLM at all
    let unusedStub = StubIntentClassifierBackend(responses: [])
    let store3 = AppStore(
        intentClassifier: IntentClassifier(backend: unusedStub),
        intentBackendMode: .rule
    )
    store3.input = "0x2222222222222222222222222222222222222222"
    store3.chatQuestion = "给这个地址转 5 USDC"
    await store3.askAboutSelectedContext()
    try suite.equal(unusedStub.callCount, 0, "rule mode skips LLM classifier")
    try suite.equal(store3.floatingWalletIntent?.action, WalletIntentAction.transfer, "rule mode still produces intent via parser")
}
```

Wire it into `run()`:

```swift
try testIntentClassifierPrompt(&suite)
try await testAppStoreIntentDispatch(&suite)    // NEW
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: fails at "stub swap intent applied to store" because `handleWalletIntentIfNeeded` still uses only the rule parser.

- [ ] **Step 3: Rewrite `handleWalletIntentIfNeeded`**

In `Sources/AgentWallet/Stores/AppStore.swift`, replace the existing `handleWalletIntentIfNeeded` function body with this:

```swift
private func handleWalletIntentIfNeeded(
    context: String,
    question: String,
    sessionID: ContextChatSession.ID?
) async -> Bool {
    let previousIntent = floatingWalletIntent
    let chain = selectedTradeChain

    // Try LLM unless flag forces rules.
    if !intentBackendMode.skipsLLM {
        do {
            let structured = try await intentClassifier.classify(
                selectedContext: context,
                previousIntent: previousIntent,
                chainHint: chain.id,
                question: question
            )
            if let handled = await dispatchStructuredIntent(
                structured,
                context: context,
                sessionID: sessionID
            ) {
                return handled
            }
        } catch {
            llmErrorMessage = "意图分类降级:\(error.localizedDescription)"
        }
    }

    // Fallback path: rule parser.
    let draft = WalletIntentParser.parse(
        selectedText: context,
        question: question,
        chain: chain,
        continuing: previousIntent
    )
    return await dispatchRuleDraft(draft, sessionID: sessionID)
}

/// Returns nil when the structured intent maps to a draft action whose
/// handling matches the existing rule-based flow (so we delegate to the
/// shared dispatcher). Returns true/false for actions handled inline
/// (check_*, unsupported, ask).
private func dispatchStructuredIntent(
    _ intent: StructuredIntent,
    context: String,
    sessionID: ContextChatSession.ID?
) async -> Bool? {
    switch intent.action {
    case .ask:
        return false
    case .unsupported:
        let reason = intent.unsupportedReason.isEmpty ? "这个操作暂不支持。" : intent.unsupportedReason
        appendMessage(ContextChatMessage(role: .assistant, text: reason), to: sessionID)
        return true
    case .transfer, .swap:
        guard let draft = intent.toWalletIntentDraft(
            selectedContext: context,
            fallbackChain: selectedTradeChain
        ) else {
            return false
        }
        return await dispatchRuleDraft(draft, sessionID: sessionID)
    case .checkBalance, .checkToken, .checkTx, .checkAddress:
        // Implemented in Task 13. For now, behave as ask.
        return false
    }
}

private func dispatchRuleDraft(
    _ intent: WalletIntentDraft,
    sessionID: ContextChatSession.ID?
) async -> Bool {
    guard intent.action != .ask else {
        return false
    }

    resetFloatingWalletAction(clearTradePlan: true)
    floatingWalletIntent = intent

    if !intent.missingFields.isEmpty {
        let message = "我识别到\(intent.action.title)意图,但还缺:\(intent.missingFieldsText)。请补充清楚后我再生成确认单。"
        floatingWalletActionErrorMessage = message
        appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
        return true
    }

    appendMessage(ContextChatMessage(role: .assistant, text: intent.confirmationSummary), to: sessionID)
    isBuildingFloatingWalletAction = true
    floatingWalletActionStatusMessage = "正在生成\(intent.action.title)确认单。"
    floatingWalletActionErrorMessage = nil

    switch intent.action {
    case .transfer:
        await buildFloatingTransferPlan(intent, sessionID: sessionID)
    case .swap:
        await buildFloatingSwapPlan(intent, sessionID: sessionID)
    case .unsupported:
        let message = "这个钱包操作暂不支持,我不会生成可签名交易。"
        floatingWalletActionErrorMessage = message
        appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
    case .ask:
        break
    }

    isBuildingFloatingWalletAction = false
    return true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS on all three branches (LLM success, fallback after retry exhaustion, forced-rule mode).

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Stores/AppStore.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Route handleWalletIntentIfNeeded through LLM classifier first

AppStore now consults the IntentClassifier for transfer / swap /
unsupported / ask actions, falling back to WalletIntentParser on any
classifier failure. The CLIPMIND_INTENT_BACKEND=rule flag bypasses the
LLM entirely. check_* actions still degrade to ask until Task 13.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Dispatch `check_balance / check_address / check_token / check_tx`

**Files:**
- Modify: `Sources/AgentWallet/Stores/AppStore.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add this new test function:

```swift
@MainActor
private static func testAppStoreCheckActions(_ suite: inout CoreSelfTestSuite) async throws {
    // check_balance with no wallet → assistant message, no crash, no LLM call to refresh
    let balanceJSON = """
    {"action":"check_balance","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
    """
    let store = AppStore(
        intentClassifier: IntentClassifier(backend: StubIntentClassifierBackend(responses: [.success(balanceJSON)])),
        intentBackendMode: .auto
    )
    store.input = "余额"
    store.chatQuestion = "查一下我的钱包余额"
    await store.askAboutSelectedContext()
    try suite.check(
        store.chatMessages.last?.text.contains("先创建") == true || store.chatMessages.last?.text.contains("钱包") == true,
        "check_balance no-wallet shows guidance"
    )

    // check_address with empty target_address but with target_query → degrades to check_token (no crash)
    let degradeJSON = """
    {"action":"check_address","chain":null,"target_address":"","target_query":"uniswap","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
    """
    let store2 = AppStore(
        intentClassifier: IntentClassifier(backend: StubIntentClassifierBackend(responses: [.success(degradeJSON)])),
        intentBackendMode: .auto
    )
    store2.input = "uniswap"
    store2.chatQuestion = "这个项目什么风险"
    await store2.askAboutSelectedContext()
    // No assertions on Surf results (no network) — assert no fatal state corruption.
    try suite.equal(store2.errorMessage, nil, "check_address degraded path does not set errorMessage")

    // check_tx with empty hash → falls through to ask (no crash)
    let askyTxJSON = """
    {"action":"check_tx","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
    """
    let store3 = AppStore(
        intentClassifier: IntentClassifier(backend: StubIntentClassifierBackend(responses: [.success(askyTxJSON)])),
        intentBackendMode: .auto
    )
    store3.input = "随便"
    store3.chatQuestion = "这笔交易怎么样"
    await store3.askAboutSelectedContext()
    try suite.equal(store3.errorMessage, nil, "check_tx degraded path does not set errorMessage")
}
```

Wire it in:

```swift
try await testAppStoreIntentDispatch(&suite)
try await testAppStoreCheckActions(&suite)    // NEW
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: build succeeds but `check_balance no-wallet shows guidance` may fail because today the check_balance branch returns false (degrades to ask) and no guidance message is appended.

- [ ] **Step 3: Implement `check_*` dispatch**

In `Sources/AgentWallet/Stores/AppStore.swift`, replace the `case .checkBalance, .checkToken, .checkTx, .checkAddress:` arm of `dispatchStructuredIntent` with:

```swift
    case .checkBalance:
        await handleCheckBalance(sessionID: sessionID)
        return true
    case .checkAddress:
        return await handleCheckAddress(intent, sessionID: sessionID)
    case .checkToken:
        return await handleCheckToken(intent, sessionID: sessionID)
    case .checkTx:
        return await handleCheckTx(intent, sessionID: sessionID)
```

Then add these four methods to `AppStore` (place them near the existing intent handlers):

```swift
private func handleCheckBalance(sessionID: ContextChatSession.ID?) async {
    guard localWalletAccount != nil else {
        let message = "还没有本地钱包。请先在主窗口创建或导入,再来查余额。"
        appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
        return
    }
    appendMessage(ContextChatMessage(role: .assistant, text: "正在刷新本地钱包各链余额,请稍候。"), to: sessionID)
    await refreshSupportedWalletAssets()
    let summary = buildBalanceSummary()
    appendMessage(ContextChatMessage(role: .assistant, text: summary), to: sessionID)
}

private func buildBalanceSummary() -> String {
    guard !walletChainAssets.isEmpty else {
        return "暂无可用余额数据,请稍后重试。"
    }
    let lines = walletChainAssets.map { assets -> String in
        "\(assets.chain.displayName): Gas \(assets.gasText) · \(assets.assetSummary)"
    }
    return (["本地钱包余额:"] + lines).joined(separator: "\n")
}

private func handleCheckAddress(_ intent: StructuredIntent, sessionID: ContextChatSession.ID?) async -> Bool {
    if !intent.targetAddress.isEmpty {
        await runCheckResearch(
            query: intent.targetAddress,
            kind: .wallet,
            chainID: intent.chain,
            sessionID: sessionID
        )
        return true
    }

    if !intent.targetQuery.isEmpty {
        await runCheckResearch(
            query: intent.targetQuery,
            kind: .project,
            chainID: intent.chain,
            sessionID: sessionID
        )
        return true
    }

    return false
}

private func handleCheckToken(_ intent: StructuredIntent, sessionID: ContextChatSession.ID?) async -> Bool {
    if !intent.targetAddress.isEmpty {
        await runCheckResearch(
            query: intent.targetAddress,
            kind: .token,
            chainID: intent.chain,
            sessionID: sessionID
        )
        return true
    }

    if !intent.targetQuery.isEmpty {
        await runCheckResearch(
            query: intent.targetQuery,
            kind: .project,
            chainID: intent.chain,
            sessionID: sessionID
        )
        return true
    }

    return false
}

private func handleCheckTx(_ intent: StructuredIntent, sessionID: ContextChatSession.ID?) async -> Bool {
    guard !intent.transactionHash.isEmpty else {
        return false
    }
    await runCheckResearch(
        query: intent.transactionHash,
        kind: .transaction,
        chainID: intent.chain,
        sessionID: sessionID
    )
    return true
}

private func runCheckResearch(
    query: String,
    kind: QueryKind,
    chainID: String?,
    sessionID: ContextChatSession.ID?
) async {
    appendMessage(
        ContextChatMessage(
            role: .assistant,
            text: "正在用 Surf 查 \(query) 的链上信息,完整证据会在主窗口展开。"
        ),
        to: sessionID
    )
    input = query
    selectedKind = kind
    if let chainID,
       let filter = ChainFilter.all.first(where: { $0.id == chainID }) {
        selectChain(filter)
    }
    await runResearch()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS on all check_* paths. Note: check_address/check_token/check_tx with non-empty fields will actually invoke `runResearch` which calls Surf — in tests Surf isn't installed/responding, but `runResearch` already handles errors by setting `errorMessage`. The test only asserts no crash and that errorMessage is nil for the *empty-field degrade-to-ask* path.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Stores/AppStore.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Dispatch check_balance / check_address / check_token / check_tx

check_balance shows guidance when no local wallet exists, otherwise
refreshes and summarizes. check_address / check_token / check_tx route
into the existing runResearch flow with the right QueryKind. Empty
target fields degrade to ask so downstream code never crashes on bad
LLM output.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: State preservation — `ask / check_* / unsupported` must NOT clear the active intent

**Files:**
- Modify: `Sources/AgentWallet/Stores/AppStore.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add this new test function:

```swift
@MainActor
private static func testAppStoreIntentStatePreservation(_ suite: inout CoreSelfTestSuite) async throws {
    // First message: produce a swap intent and let it stick.
    let swapJSON = """
    {"action":"swap","chain":"base","target_address":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
    """
    let askJSON = """
    {"action":"ask","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
    """
    let unsupportedJSON = """
    {"action":"unsupported","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":"NFT mint 暂未支持"}
    """
    let stub = StubIntentClassifierBackend(responses: [
        .success(swapJSON),
        .success(askJSON),
        .success(unsupportedJSON)
    ])
    let store = AppStore(
        intentClassifier: IntentClassifier(backend: stub),
        intentBackendMode: .auto
    )
    store.input = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
    store.chatQuestion = "用 5u 买这个"
    await store.askAboutSelectedContext()
    try suite.equal(store.floatingWalletIntent?.action, WalletIntentAction.swap, "initial swap intent set")
    let swapID = store.floatingWalletIntent?.id

    // ask — must preserve swap intent
    store.chatQuestion = "这个币背景是什么"
    await store.askAboutSelectedContext()
    try suite.equal(store.floatingWalletIntent?.action, WalletIntentAction.swap, "ask preserves swap intent")
    try suite.equal(store.floatingWalletIntent?.id, swapID, "swap intent identity unchanged after ask")

    // unsupported — must also preserve swap intent
    store.chatQuestion = "我也想 mint 一个 NFT 给这个地址"
    await store.askAboutSelectedContext()
    try suite.equal(store.floatingWalletIntent?.action, WalletIntentAction.swap, "unsupported preserves swap intent")
    try suite.equal(store.floatingWalletIntent?.id, swapID, "swap intent identity unchanged after unsupported")
}
```

Wire it in:

```swift
try await testAppStoreCheckActions(&suite)
try await testAppStoreIntentStatePreservation(&suite)    // NEW
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: fails at "unsupported preserves swap intent" because the current `dispatchStructuredIntent` for `.unsupported` falls into the assistant-message path but doesn't call `resetFloatingWalletAction` — but the previous run of `dispatchRuleDraft` (via the LLM path) may have already done so. Inspect the test output to confirm; if it passes, lock the contract. If it fails, audit and fix the reset call in `dispatchStructuredIntent` for `.unsupported` to ensure it doesn't touch floatingWalletIntent.

- [ ] **Step 3: Audit reset calls**

In `Sources/AgentWallet/Stores/AppStore.swift`, verify:

- `dispatchStructuredIntent`'s `.unsupported` branch only calls `appendMessage`, never `resetFloatingWalletAction`. If it does, remove the reset call.
- `dispatchStructuredIntent`'s check_* branches do NOT call `resetFloatingWalletAction(clearTradePlan: true)` directly. The `runResearch` and `refreshSupportedWalletAssets` calls don't mutate `floatingWalletIntent` themselves.
- The `ask` early-return path (`return false`) doesn't touch intent.

If the test was already passing in Step 2, no source change needed.

If anything reset state, fix it: `.unsupported` should only `appendMessage` and return true. Same for `.checkBalance` etc.

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS for all preservation assertions.

- [ ] **Step 5: Commit (only if Step 3 made changes)**

```bash
git add Sources/AgentWallet/Stores/AppStore.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Preserve active wallet intent across ask / unsupported turns

Locks the spec rule: investigating mid-swap (ask) or stumbling into an
unsupported branch must not drop the pending transfer/swap intent.
Adds regression tests that an active swap intent survives subsequent
ask and unsupported turns by intent identity.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

If Step 3 made no source change, commit only the test file:

```bash
git add Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Lock intent state preservation rule with regression test

No source change needed — the existing dispatch already preserves
active intents across ask / unsupported turns. Test pins the contract
so future refactors don't regress it.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Full verification

**Files:** none modified; this is the smoke-test pass.

- [ ] **Step 1: Run the core self-test suite**

Run: `./script/test.sh`
Expected: prints `self_test_core=ok` and `passed=N` where N is the count after all new tests landed. Every line above must be `pass:`.

- [ ] **Step 2: Build the release binary**

Run: `./script/build_and_run.sh --verify`
Expected: build succeeds, app process launches, verification confirms the process is alive.

- [ ] **Step 3: Manual smoke (LLM path)**

This step requires a B.AI API key. Skip if no key:

```bash
export CLIPMIND_INTENT_BACKEND=auto
./script/build_and_run.sh
```

In the running app:
- Open the floating panel (`Ctrl+Opt+W`)
- Type `这个项目可以质押吗` with `Aave` selected → expect a Chinese assistant message saying staking 暂未支持
- Select a wallet address, ask `这个地址安全吗` → expect runResearch to fire (you'll see Surf commands appear in main window)

- [ ] **Step 4: Manual smoke (rule fallback path)**

```bash
export CLIPMIND_INTENT_BACKEND=rule
./script/build_and_run.sh
```

- Select an address, type `给这个地址转 5 USDC` → expect transfer confirmation card
- Type `这个地址有什么风险` → expect plain Chinese Q&A (no Surf auto-trigger because rules don't know check_address)

- [ ] **Step 5: Update IMPLEMENTATION_NOTES.md**

Append to `IMPLEMENTATION_NOTES.md` under "已完成内容":

```
19. 接入 LLM 结构化意图分类器(StructuredIntent + IntentClassifier)。LLM 先出 JSON,失败时退到 WalletIntentParser 规则解析。新增 4 个只读 check_* 动作,自动驱动钱包余额或 Surf 链上查询。用 `CLIPMIND_INTENT_BACKEND=rule` 可强制关闭 LLM 分类。
```

- [ ] **Step 6: Commit doc update**

```bash
git add IMPLEMENTATION_NOTES.md
git commit -m "$(cat <<'EOF'
Document LLM intent classifier in implementation notes

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

**Spec coverage**
- §1 file structure → Tasks 1, 6, 9, 11–14
- §2 schema + adapter → Tasks 1, 2, 5
- §3 prompt + retry + token limits → Tasks 7, 9
- §4 dispatch (8 actions) + state preservation → Tasks 12, 13, 14
- §5 error degradation → Tasks 7, 8, 12 (fallback)
- §6 testing → All TDD tasks; Task 15 runs full suite
- §7 flag + rollout → Tasks 11, 12, 15 (manual smoke under both modes)

**Type / signature consistency**
- `StructuredIntentAction` raw values use `check_balance` etc. snake_case to match wire format; Swift cases use camelCase (`checkBalance`). Adapter and tests both use the camelCase form.
- `StructuredIntent.toWalletIntentDraft(selectedContext:fallbackChain:)` signature consistent across Tasks 5, 12, 13.
- `IntentClassifierBackend.classifyChat(system:user:)` consistent in Tasks 6, 10.
- `IntentClassifier.classify(selectedContext:previousIntent:chainHint:question:)` consistent in Tasks 6, 7, 8, 12.

**No placeholders detected.** All code blocks are complete. The placeholder `IntentClassifierPrompt` in Task 6 is intentional and removed in Task 9.
