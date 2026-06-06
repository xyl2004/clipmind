# Tx Record In Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Append broadcast results (success or failure) into the floating chat as assistant messages, with clickable explorer URLs, so the conversation history carries the operation outcome alongside the intent confirmation card.

**Architecture:** Two new utility files: `BroadcastChatFormatter` (pure-function text templates for 3 action types × success/failure) and `ChatBubbleAttributedString` (NSDataDetector-based URL→link conversion). `FloatingChatBubble` renders all assistant text through the AttributedString helper. `AppStore.signAndBroadcastTrade` and `signAndBroadcastTransfer` each capture an `recordSessionID` at the top and append one chat message per outcome branch.

**Tech Stack:** Swift 5.9, SwiftPM, no XCTest. Tests live in `Sources/AgentWallet/Support/CoreSelfTests.swift` and run via `swift run ClipMind --self-test-core` (driven by `script/test.sh`).

**Spec:** `docs/superpowers/specs/2026-06-06-tx-record-in-chat-design.md`

---

## File Structure

**Create**
- `Sources/AgentWallet/Support/BroadcastChatFormatter.swift` — `BroadcastAction` enum + `formatSuccess`/`formatFailure` pure functions
- `Sources/AgentWallet/Support/ChatBubbleAttributedString.swift` — `build(_ text: String, accent: Color) -> AttributedString` using `NSDataDetector`

**Modify**
- `Sources/AgentWallet/Views/FloatingContextPanelView.swift` — `FloatingChatBubble.bubble` switches from `Text(verbatim:)` to `Text(ChatBubbleAttributedString.build(...))`
- `Sources/AgentWallet/Stores/AppStore.swift` — `signAndBroadcastTrade` and `signAndBroadcastTransfer` capture `recordSessionID` at top, append a chat message in each outcome branch
- `Sources/AgentWallet/Support/CoreSelfTests.swift` — add 2 new test functions, wire them into `run()`

**Untouched**
- `Sources/AgentWallet/Models/ResearchSnapshot.swift` — `ContextChatMessage` / `ContextChatRole` unchanged
- `Sources/AgentWallet/Views/SidebarView.swift` — main window's `TradeHistorySidebarSection` keeps working
- `tradeStatusMessage` / `floatingWalletActionStatusMessage` / error message slots — still set as before (card-area feedback)

---

## Task 1: `BroadcastChatFormatter` types and success formatting

**Files:**
- Create: `Sources/AgentWallet/Support/BroadcastChatFormatter.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add this new test function in `CoreSelfTests.swift`, placed after `testIntentClassifierPrompt`:

```swift
private static func testBroadcastChatRecordFormat(_ suite: inout CoreSelfTestSuite) throws {
    let hash = "0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
    let base = ChainRegistry.base

    let swap = BroadcastChatFormatter.formatSuccess(action: .swap, hash: hash, chain: base)
    try suite.check(swap.contains("Base 上完成 Uniswap 兑换"), "swap success header on Base")
    try suite.check(swap.contains("交易哈希："), "swap success hash row label")
    try suite.check(swap.contains("https://basescan.org/tx/\(hash)"), "swap success contains explorer URL")

    let approval = BroadcastChatFormatter.formatSuccess(
        action: .swapApproval(spendSymbol: "USDC"),
        hash: hash,
        chain: base
    )
    try suite.check(approval.contains("USDC 授权"), "approval success names spend symbol")
    try suite.check(approval.contains("授权上链后"), "approval success has next-step hint")
    try suite.check(approval.contains("https://basescan.org/tx/\(hash)"), "approval success contains explorer URL")

    let transfer = BroadcastChatFormatter.formatSuccess(action: .transfer, hash: hash, chain: base)
    try suite.check(transfer.contains("Base 上广播转账"), "transfer success header on Base")
    try suite.check(transfer.contains("https://basescan.org/tx/\(hash)"), "transfer success contains explorer URL")
}
```

Wire it into `run()`:

```swift
try testIntentClassifierPrompt(&suite)
try testBroadcastChatRecordFormat(&suite)    // NEW
try await testAppStoreIntentDispatch(&suite)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: build fails with `cannot find 'BroadcastChatFormatter' in scope`.

- [ ] **Step 3: Implement `BroadcastChatFormatter` with success**

Create `Sources/AgentWallet/Support/BroadcastChatFormatter.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS with `pass: swap success header on Base`, `pass: approval success names spend symbol`, etc.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Support/BroadcastChatFormatter.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Add BroadcastChatFormatter with success templates

Pure-function text templates for three broadcast action types
(swap / swapApproval / transfer). Each success message has a
chain-aware header, short hash line, and full explorer URL on its
own line for clickable detection later.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `BroadcastChatFormatter` failure formatting

**Files:**
- Modify: `Sources/AgentWallet/Support/BroadcastChatFormatter.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Append to `testBroadcastChatRecordFormat`:

```swift
    let swapFail = BroadcastChatFormatter.formatFailure(
        action: .swap,
        error: SampleBroadcastError.network
    )
    try suite.check(swapFail.contains("广播 Uniswap 兑换失败"), "swap failure label")
    try suite.check(swapFail.contains("报价新鲜度"), "swap failure hint mentions quote freshness")
    try suite.check(swapFail.contains("测试用网络错误"), "swap failure quotes underlying error")

    let transferFail = BroadcastChatFormatter.formatFailure(
        action: .transfer,
        error: SampleBroadcastError.network
    )
    try suite.check(transferFail.contains("广播转账失败"), "transfer failure label")
    try suite.check(transferFail.contains("收款地址"), "transfer failure hint mentions recipient")

    let approvalFail = BroadcastChatFormatter.formatFailure(
        action: .swapApproval(spendSymbol: "USDC"),
        error: SampleBroadcastError.network
    )
    try suite.check(approvalFail.contains("广播授权失败"), "approval failure label")
    try suite.check(approvalFail.contains("Gas 余额"), "approval failure hint mentions gas")
```

Add this private enum at the bottom of `CoreSelfTests`, right above `CoreSelfTestSuite`:

```swift
private enum SampleBroadcastError: LocalizedError {
    case network

    var errorDescription: String? {
        switch self {
        case .network:
            return "测试用网络错误"
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: build fails with `value of type 'BroadcastChatFormatter.Type' has no member 'formatFailure'`.

- [ ] **Step 3: Implement `formatFailure`**

Append to `Sources/AgentWallet/Support/BroadcastChatFormatter.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS with `pass: swap failure label`, `pass: transfer failure hint mentions recipient`, etc.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Support/BroadcastChatFormatter.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Add BroadcastChatFormatter failure templates

Action-aware failure messages with localized error description and a
short troubleshooting hint per action (swap mentions quote freshness,
transfer mentions recipient, approval mentions gas).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `ChatBubbleAttributedString` URL→link conversion

**Files:**
- Create: `Sources/AgentWallet/Support/ChatBubbleAttributedString.swift`
- Modify: `Sources/AgentWallet/Support/CoreSelfTests.swift`

- [ ] **Step 1: Write failing test**

Add this new test function after `testBroadcastChatRecordFormat`:

```swift
private static func testChatBubbleAttributedString(_ suite: inout CoreSelfTestSuite) throws {
    let single = ChatBubbleAttributedString.build("查 https://basescan.org/tx/0xabc 看详情")
    try suite.equal(String(single.characters), "查 https://basescan.org/tx/0xabc 看详情", "build keeps original text")
    var foundLink = false
    for run in single.runs where run.link != nil {
        foundLink = true
    }
    try suite.check(foundLink, "URL detected and link attribute set")

    let none = ChatBubbleAttributedString.build("这段没有链接")
    for run in none.runs {
        try suite.check(run.link == nil, "no link in plain text run")
    }

    let two = ChatBubbleAttributedString.build("https://a.example 和 https://b.example 都看")
    var linkCount = 0
    for run in two.runs where run.link != nil {
        linkCount += 1
    }
    try suite.check(linkCount >= 1, "at least one URL detected when multiple present")
}
```

Wire it into `run()`:

```swift
try testBroadcastChatRecordFormat(&suite)
try testChatBubbleAttributedString(&suite)    // NEW
try await testAppStoreIntentDispatch(&suite)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./script/test.sh`
Expected: build fails with `cannot find 'ChatBubbleAttributedString' in scope`.

- [ ] **Step 3: Implement `ChatBubbleAttributedString.build`**

Create `Sources/AgentWallet/Support/ChatBubbleAttributedString.swift`:

```swift
import AppKit
import Foundation
import SwiftUI

enum ChatBubbleAttributedString {
    static func build(_ text: String, accent: Color = AppTheme.accent) -> AttributedString {
        var attributed = AttributedString(text)

        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return attributed
        }

        let nsText = text as NSString
        let matches = detector.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )

        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let attrRange = attributed.range(of: String(text[range])) else {
                continue
            }
            attributed[attrRange].link = url
            attributed[attrRange].foregroundColor = accent
            attributed[attrRange].underlineStyle = .single
        }

        return attributed
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./script/test.sh`
Expected: PASS with `pass: build keeps original text`, `pass: URL detected and link attribute set`, etc.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Support/ChatBubbleAttributedString.swift Sources/AgentWallet/Support/CoreSelfTests.swift
git commit -m "$(cat <<'EOF'
Add ChatBubbleAttributedString URL detection helper

Pure function that takes a plain String and returns an AttributedString
with NSDataDetector-recognized URLs marked as clickable links (accent
color + single underline). Non-URL spans stay plain text. Used by the
floating chat bubble in the next task.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Wire AttributedString into `FloatingChatBubble`

**Files:**
- Modify: `Sources/AgentWallet/Views/FloatingContextPanelView.swift`

No unit test — SwiftUI rendering is not assertable in `CoreSelfTests`. Verified by build + smoke test in Task 7.

- [ ] **Step 1: Locate the existing chat bubble text**

In `Sources/AgentWallet/Views/FloatingContextPanelView.swift`, find the `FloatingChatBubble` struct's `bubble` computed property (around line 559). It currently reads:

```swift
private var bubble: some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(message.role == .assistant ? "AI" : "你")
            .font(.caption)
            .foregroundStyle(AppTheme.mutedText)
        Text(verbatim: message.text)
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .frame(maxWidth: 480, alignment: .leading)
    .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AppTheme.border.opacity(message.role == .assistant ? 1 : 0), lineWidth: 1)
    )
}
```

- [ ] **Step 2: Switch to `AttributedString`**

Replace the `Text(verbatim: message.text)` line with:

```swift
        Text(ChatBubbleAttributedString.build(message.text))
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
```

The full `bubble` property after edit:

```swift
private var bubble: some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(message.role == .assistant ? "AI" : "你")
            .font(.caption)
            .foregroundStyle(AppTheme.mutedText)
        Text(ChatBubbleAttributedString.build(message.text))
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .frame(maxWidth: 480, alignment: .leading)
    .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AppTheme.border.opacity(message.role == .assistant ? 1 : 0), lineWidth: 1)
    )
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Run self-tests to confirm no regression**

Run: `./script/test.sh`
Expected: existing `passed=N` count holds, plus any new asserts from Tasks 1-3.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Views/FloatingContextPanelView.swift
git commit -m "$(cat <<'EOF'
Render floating chat bubbles through ChatBubbleAttributedString

User bubbles and assistant bubbles both go through the URL-detecting
helper, so any URL appearing in chat — broadcast tx records, LLM
explanations citing Surf links, future content — becomes clickable
on macOS via the SwiftUI link handler.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire `BroadcastChatFormatter` into `signAndBroadcastTrade`

**Files:**
- Modify: `Sources/AgentWallet/Stores/AppStore.swift`

No new unit test — `LocalWalletClient` is not protocol-abstracted, real broadcast requires network. Verified by Task 7 manual run.

- [ ] **Step 1: Locate the existing method body**

In `Sources/AgentWallet/Stores/AppStore.swift`, find `signAndBroadcastTrade()`. The do/catch block currently reads (around line 750-770):

```swift
isSigningTrade = true
tradeStatusMessage = tradePlan.needsApproval ? "正在本机签名授权交易。" : "正在本机签名并广播 swap。"
tradeErrorMessage = nil

do {
    let hash = try await localWalletClient.signAndBroadcast(transaction, chain: tradePlan.chain)
    let explorerPrefix = tradePlan.chain.explorerTransactionURLPrefix
    if tradePlan.needsApproval {
        tradeStatusMessage = "授权交易已广播：\(hash)\n\(explorerPrefix)/\(hash)\n授权上链后请重新生成报价，再签名兑换。"
        addTradeHistory(hash: hash, chain: tradePlan.chain, action: "授权")
    } else {
        tradeStatusMessage = "交易已广播：\(hash)\n\(explorerPrefix)/\(hash)"
        addTradeHistory(hash: hash, chain: tradePlan.chain, action: "兑换")
    }
    self.tradePlan = nil
    tradeConfirmationText = ""
} catch {
    tradeErrorMessage = error.localizedDescription
    tradeStatusMessage = nil
}

isSigningTrade = false
```

- [ ] **Step 2: Capture `recordSessionID` and inject chat appends**

Replace the block in Step 1 with this:

```swift
let recordSessionID = activeChatSessionID
isSigningTrade = true
tradeStatusMessage = tradePlan.needsApproval ? "正在本机签名授权交易。" : "正在本机签名并广播 swap。"
tradeErrorMessage = nil

do {
    let hash = try await localWalletClient.signAndBroadcast(transaction, chain: tradePlan.chain)
    let explorerPrefix = tradePlan.chain.explorerTransactionURLPrefix
    let recordAction: BroadcastAction
    if tradePlan.needsApproval {
        tradeStatusMessage = "授权交易已广播：\(hash)\n\(explorerPrefix)/\(hash)\n授权上链后请重新生成报价，再签名兑换。"
        addTradeHistory(hash: hash, chain: tradePlan.chain, action: "授权")
        recordAction = .swapApproval(spendSymbol: tradePlan.inputToken.symbol)
    } else {
        tradeStatusMessage = "交易已广播：\(hash)\n\(explorerPrefix)/\(hash)"
        addTradeHistory(hash: hash, chain: tradePlan.chain, action: "兑换")
        recordAction = .swap
    }
    appendMessage(
        ContextChatMessage(
            role: .assistant,
            text: BroadcastChatFormatter.formatSuccess(
                action: recordAction,
                hash: hash,
                chain: tradePlan.chain
            )
        ),
        to: recordSessionID
    )
    self.tradePlan = nil
    tradeConfirmationText = ""
} catch {
    let failureAction: BroadcastAction = tradePlan.needsApproval
        ? .swapApproval(spendSymbol: tradePlan.inputToken.symbol)
        : .swap
    appendMessage(
        ContextChatMessage(
            role: .assistant,
            text: BroadcastChatFormatter.formatFailure(action: failureAction, error: error)
        ),
        to: recordSessionID
    )
    tradeErrorMessage = error.localizedDescription
    tradeStatusMessage = nil
}

isSigningTrade = false
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Run self-tests to confirm no regression**

Run: `./script/test.sh`
Expected: `passed=N` count unchanged from after Task 4.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Stores/AppStore.swift
git commit -m "$(cat <<'EOF'
Append swap broadcast results to the floating chat

signAndBroadcastTrade now captures the chat session at the top, then
appends one assistant message per outcome (approval success, swap
success, or failure with action-specific hint). Existing card-area
status and trade history flows are untouched — the chat append is
additive so users see both the immediate card feedback and a
permanent record in the session.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Wire `BroadcastChatFormatter` into `signAndBroadcastTransfer`

**Files:**
- Modify: `Sources/AgentWallet/Stores/AppStore.swift`

- [ ] **Step 1: Locate the existing method body**

Find the do/catch block in `signAndBroadcastTransfer()` (around line 815-830):

```swift
isSigningTransfer = true
floatingWalletActionStatusMessage = "正在本机签名并广播转账。"
floatingWalletActionErrorMessage = nil

do {
    let hash = try await localWalletClient.signAndBroadcast(
        transferPlan.transaction,
        chain: transferPlan.chain
    )
    let explorerPrefix = transferPlan.chain.explorerTransactionURLPrefix
    floatingWalletActionStatusMessage = "转账已广播：\(hash)\n\(explorerPrefix)/\(hash)"
    addTradeHistory(hash: hash, chain: transferPlan.chain, action: "转账")
    self.transferPlan = nil
    transferConfirmationText = ""
} catch {
    floatingWalletActionErrorMessage = error.localizedDescription
    floatingWalletActionStatusMessage = nil
}

isSigningTransfer = false
```

- [ ] **Step 2: Capture `recordSessionID` and inject chat appends**

Replace the block in Step 1 with this:

```swift
let recordSessionID = activeChatSessionID
isSigningTransfer = true
floatingWalletActionStatusMessage = "正在本机签名并广播转账。"
floatingWalletActionErrorMessage = nil

do {
    let hash = try await localWalletClient.signAndBroadcast(
        transferPlan.transaction,
        chain: transferPlan.chain
    )
    let explorerPrefix = transferPlan.chain.explorerTransactionURLPrefix
    floatingWalletActionStatusMessage = "转账已广播：\(hash)\n\(explorerPrefix)/\(hash)"
    addTradeHistory(hash: hash, chain: transferPlan.chain, action: "转账")
    appendMessage(
        ContextChatMessage(
            role: .assistant,
            text: BroadcastChatFormatter.formatSuccess(
                action: .transfer,
                hash: hash,
                chain: transferPlan.chain
            )
        ),
        to: recordSessionID
    )
    self.transferPlan = nil
    transferConfirmationText = ""
} catch {
    appendMessage(
        ContextChatMessage(
            role: .assistant,
            text: BroadcastChatFormatter.formatFailure(action: .transfer, error: error)
        ),
        to: recordSessionID
    )
    floatingWalletActionErrorMessage = error.localizedDescription
    floatingWalletActionStatusMessage = nil
}

isSigningTransfer = false
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Run self-tests to confirm no regression**

Run: `./script/test.sh`
Expected: `passed=N` count unchanged from after Task 5.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentWallet/Stores/AppStore.swift
git commit -m "$(cat <<'EOF'
Append transfer broadcast results to the floating chat

signAndBroadcastTransfer captures the chat session and emits one
assistant message per outcome (transfer success or transfer failure).
The card-area status and trade history flows are untouched — the chat
append is additive.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Full verification

**Files:** none modified; smoke pass.

- [ ] **Step 1: Run the core self-test suite**

Run: `./script/test.sh`
Expected: prints `self_test_core=ok` and a `passed=N` line where N includes all asserts from Tasks 1-3 in addition to existing tests.

- [ ] **Step 2: Build the release bundle**

Run: `./script/build_and_run.sh --verify`
Expected: build succeeds, app launches, process verified alive.

- [ ] **Step 3: Manual smoke — transfer with chat record**

Launch in auto mode:

```bash
pkill -x ClipMind 2>/dev/null
CLIPMIND_INTENT_BACKEND=auto nohup ./dist/ClipMind.app/Contents/MacOS/ClipMind >/tmp/clipmind-auto.log 2>&1 &
```

- Select a recipient address in any app
- `Ctrl+Opt+W`
- Type `转 0.0001 ETH 给这个地址`
- After confirmation card appears, type the confirmation code, click `本机签名并发送`
- Expected chat after success:
  - User: `转 0.0001 ETH 给这个地址`
  - AI: confirmation summary
  - AI: `已在 Base 上广播转账。\n交易哈希：0x… (短)\nhttps://basescan.org/tx/0x…` (full URL is clickable, opens browser to BaseScan)

- [ ] **Step 4: Manual smoke — swap with chat record**

- Select an EVM token contract (e.g. Base USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`)
- Type `用 0.001 ETH 买这个`
- Confirm and sign
- Expected chat after success:
  - AI: `已在 Base 上完成 Uniswap 兑换。\n交易哈希：0x…\nhttps://basescan.org/tx/0x…`
- Click the URL → BaseScan opens in browser.

- [ ] **Step 5: Manual smoke — failure path**

- Trigger a failure on purpose: try a swap with `spend_amount` larger than your ETH balance, or kill the network briefly before signing
- After clicking sign and seeing the error, expected chat:
  - AI: `广播 Uniswap 兑换失败：<error message>。\n可以检查 Gas 余额、报价新鲜度、网络后再试。`
  - Card area still shows the red error
  - Chat record persists when you switch sessions and come back

- [ ] **Step 6: Update IMPLEMENTATION_NOTES.md**

Append item 20 under "已完成内容":

```
20. 悬浮窗聊天里追加广播交易记录。signAndBroadcastTrade 和 signAndBroadcastTransfer 在成功 / 失败分支各 append 一条助手消息,带短哈希和完整浏览器 URL;聊天里所有助手消息现在经 ChatBubbleAttributedString 渲染,URL 自动可点击打开浏览器。
```

- [ ] **Step 7: Commit doc update**

```bash
git add IMPLEMENTATION_NOTES.md
git commit -m "$(cat <<'EOF'
Document tx record in chat in implementation notes

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

**Spec coverage**
- §1 file structure → Tasks 1, 2 (formatter), 3 (attributed string), 4-6 (modifications)
- §2 AttributedString detail → Task 3
- §3 message templates → Tasks 1, 2
- §4.1 signAndBroadcastTrade injection → Task 5 (covers all three branches including catch-block needsApproval read)
- §4.2 signAndBroadcastTransfer injection → Task 6
- §4.5 recordSessionID capture → Tasks 5, 6 (both capture at method top)
- §5 testing → Tasks 1, 2, 3 (formatter success / failure / URL detection)

**Type / signature consistency**
- `BroadcastAction` enum declared in Task 1, used identically in Tasks 2, 5, 6.
- `BroadcastChatFormatter.formatSuccess(action:hash:chain:)` signature stable across Tasks 1, 5, 6.
- `BroadcastChatFormatter.formatFailure(action:error:)` signature stable across Tasks 2, 5, 6.
- `ChatBubbleAttributedString.build(_:accent:)` consistent in Tasks 3, 4.
- `tradePlan.inputToken.symbol` reference is valid — `UniswapTradePlan` defines `inputToken: TokenProfile` (verified in `Sources/AgentWallet/Services/UniswapTradeProvider.swift`).

**No placeholders detected.** All code blocks are complete.
