# 悬浮窗聊天里追加交易记录

- 日期:2026-06-06
- 状态:Draft,待 user review
- 关联代码:`Sources/AgentWallet/Stores/AppStore.swift`(`signAndBroadcastTrade` / `signAndBroadcastTransfer`)、`Sources/AgentWallet/Views/FloatingContextPanelView.swift`(`FloatingChatBubble`)

## 背景

当前 swap 兑换或转账广播成功/失败后,反馈只出现在悬浮窗的"钱包动作卡片"区(`tradeStatusMessage` / `floatingWalletActionStatusMessage`)。卡片随 `tradePlan = nil` 和 `transferPlan = nil` 一起消失,信息存活时间短。同时 `tradeHistory` 数组会更新,但只在**主窗口左侧栏**展示。

结果:用户回头看悬浮窗的历史会话只能看到对话,看不到这次操作究竟干了什么、tx hash 是什么、链上证据在哪。

本功能把"广播结果"也作为助手消息写进聊天流,与现有对话上下文并存,**便携且可追溯**。

## 已对齐的决策

| 决策点 | 选择 |
|---|---|
| 渲染形式 | 普通助手消息(不引入新卡片组件) |
| 失败处理 | 成功 + 失败都写入聊天 |
| 浏览器链接 | 可点击直接打开浏览器 |
| 实现路径 | Approach B:所有助手消息统一用 `AttributedString` 渲染,`NSDataDetector` 自动识别 URL |

Approach A(给 `ContextChatMessage` 加 `kind` 字段 + 专用 tx 记录渲染)和 Approach C(text + 按钮)都被放弃 —— 用户明确选了"普通助手消息"路径。

## §1 文件结构和改动范围

**新增**

- `Sources/AgentWallet/Support/ChatBubbleAttributedString.swift` —— 纯函数 `build(_ text: String, accent: Color) -> AttributedString`。用 `NSDataDetector` 扫文本,把 URL 区段写成可点击 link
- `Sources/AgentWallet/Support/BroadcastChatFormatter.swift` —— 纯函数 + enum,集中所有广播结果文案模板;独立于 `AppStore` 方便单测

**改动**

- `Sources/AgentWallet/Views/FloatingContextPanelView.swift` —— `FloatingChatBubble.bubble` 里 `Text(verbatim: message.text)` 换成 `Text(ChatBubbleAttributedString.build(message.text))`。其他属性不动(`.textSelection(.enabled)` 保留)
- `Sources/AgentWallet/Stores/AppStore.swift` —— `signAndBroadcastTrade` 和 `signAndBroadcastTransfer` 的成功/失败分支调用 `appendMessage(ContextChatMessage(role: .assistant, text: BroadcastChatFormatter.formatSuccess(...) 或 formatFailure(...)), to: activeChatSessionID)`
- `Sources/AgentWallet/Support/CoreSelfTests.swift` —— 加 §5 列出的两组测试

**不动**

- `ContextChatMessage` / `ContextChatRole` —— 模型零改动
- `TradeHistorySidebarSection`(主窗口左栏交易历史)—— 继续工作,不与悬浮窗聊天记录互斥
- `tradeHistory` 数组 —— 继续维护
- `tradeStatusMessage` / `floatingWalletActionStatusMessage` / `tradeErrorMessage` / `floatingWalletActionErrorMessage` —— 继续设置(交易卡片区即时反馈),新功能**追加**到聊天,不**替代**

**关键决定**:`AttributedString` 路径是普惠的 —— LLM 中文解读和 `runCheckResearch` 写的 "Surf 查询" 消息里的 URL 一并变可点击,这是有意外溢出收益,不是 bug。

## §2 `AttributedString` 构建细节

**`ChatBubbleAttributedString.build(_:accent:)` 主体逻辑**

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

**关键决定与已知限制**

1. **NSDataDetector 覆盖**:认 `http://`、`https://`、裸 `www.`、协议未指定的 URL,对本项目场景(基本都是 `https://...scan.../tx/...`)够用
2. **范围转换**:`NSRange (UTF-16 单位)→ Range<String.Index>→ AttributedString.Range`,用 `attributed.range(of:)` 而不是手动按字符偏移算,稳
3. **重复子串问题**:同一 URL 在文本里出现两次时,`range(of:)` 只匹配首次 → 只有首个 link 可点。tx 记录每条只有一个 URL,LLM 解读里极少重复,接受第一版限制。后续如出现 bug 再换成基于 NSRange.location 的索引方式
4. **`.textSelection(.enabled)`**:仍保留;`Text(AttributedString)` + `.textSelection(.enabled)` 在 macOS SwiftUI 下兼容 —— URL 区段可点击,其余文本可选中
5. **空字符串/无 URL 短路**:detector 失败或 `matches.isEmpty` 时直接返回原 `AttributedString`,无副作用
6. **link 视觉**:带 `accent` 色 + `.single` 下划线,跟项目原有强调色一致

**点击行为**:`Text(AttributedString)` 在 macOS 上由 SwiftUI 自动注册 OS 级 link 处理,点击调 `NSWorkspace.shared.open(url)`。无需手动接 gesture。

## §3 tx 记录文案模板

**统一格式**:动作行 → 哈希行 → 浏览器 URL 行 → 可选提示行。URL 单独成行让点击命中率高,与上下文文字不连写。

### 成功

**原生 ETH swap(无授权)**

```
已在 Base 上完成 Uniswap 兑换。
交易哈希：0x… (短显示)
https://basescan.org/tx/0x…(完整 URL,一整行)
```

**ERC-20 swap 的授权步**

```
已在 Base 上广播 USDC 授权交易。授权上链后再来生成最新报价，然后签名兑换。
交易哈希：0x…
https://basescan.org/tx/0x…
```

**ERC-20 swap 的兑换步**

```
已在 Base 上完成 Uniswap 兑换。
交易哈希：0x…
https://basescan.org/tx/0x…
```

**转账**

```
已在 Base 上广播转账。
交易哈希：0x…
https://basescan.org/tx/0x…
```

### 失败

**统一格式**:动作标签 + `error.localizedDescription` + 排查提示

- swap 失败:`广播 Uniswap 兑换失败：<error>。\n可以检查 Gas 余额、报价新鲜度、网络后再试。`
- 转账失败:`广播转账失败：<error>。\n可以检查 Gas 余额、收款地址和网络后再试。`
- 授权失败:`广播授权失败：<error>。\n可以检查 Gas 余额和网络后再试。`

### `BroadcastChatFormatter` 模块

```swift
enum BroadcastAction {
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
        return [header, "交易哈希：\(shortHash)", url].joined(separator: "\n")
    }

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

### 关键决定

- **不含 spend asset / amount / recipient 等操作详情**:已经在用户上面的 `intent.confirmationSummary` 助手消息里写过,**避免重复**
- **不显示 timestamp**:`ContextChatMessage.createdAt` 已携带,后续若要在 bubble 角落展示再加,本期不挂
- **URL 不缩短**:让 detector 能识别 + 点击区域大;短 hash 在哈希行独立显示

## §4 注入点 — `AppStore` 广播方法改造

### §4.1 `signAndBroadcastTrade`

定位三个分支(行号约 755-770):

| 分支 | 触发 | 当前行为 | 新增 |
|---|---|---|---|
| A | `needsApproval == true` & broadcast 成功 | 设 `tradeStatusMessage` + `addTradeHistory("授权")` | append 一条 `formatSuccess(.swapApproval(symbol), hash, chain)` |
| B | `needsApproval == false` & broadcast 成功 | 设 `tradeStatusMessage` + `addTradeHistory("兑换")` | append 一条 `formatSuccess(.swap, hash, chain)` |
| C | broadcast 抛错 | 设 `tradeErrorMessage` | append 一条 `formatFailure(action, error)`,action 由 `tradePlan.needsApproval` 区分 |

**catch 块识别逻辑**(假设方法开头已 `let recordSessionID = activeChatSessionID`):

```swift
} catch {
    let action: BroadcastAction = tradePlan.needsApproval
        ? .swapApproval(spendSymbol: tradePlan.inputToken.symbol)
        : .swap
    appendMessage(
        ContextChatMessage(
            role: .assistant,
            text: BroadcastChatFormatter.formatFailure(action: action, error: error)
        ),
        to: recordSessionID
    )
    tradeErrorMessage = error.localizedDescription
    tradeStatusMessage = nil
}
```

### §4.2 `signAndBroadcastTransfer`

定位两个分支(行号约 815-830):

| 分支 | 触发 | 当前行为 | 新增 |
|---|---|---|---|
| 成功 | broadcast 返回 hash | 设 `floatingWalletActionStatusMessage` + `addTradeHistory("转账")` | append 一条 `formatSuccess(.transfer, hash, chain)` |
| 失败 | broadcast 抛错 | 设 `floatingWalletActionErrorMessage` | append 一条 `formatFailure(.transfer, error)` |

### §4.3 不动的部分

- `tradeStatusMessage` / `floatingWalletActionStatusMessage` 继续设置:交易卡片区即时反馈;聊天追加是补强,不是替换
- `addTradeHistory(...)` 继续调用:主窗口左栏交易历史依然填
- `tradeErrorMessage` / `floatingWalletActionErrorMessage` 在失败分支继续设置:卡片区红色错误提示与聊天里失败记录并行
- 卡片清理(`tradePlan = nil` / `transferPlan = nil` / 重置 `confirmationText`)继续

**核心原则**:聊天记录是**追加**新输出,不替换现有输出。失败时双路并行 —— 用户立刻看到错误卡片,也能在历史里追溯。

### §4.4 时序与原子性

每个分支只 append **一条**助手消息。授权 → 兑换是两次独立的 `signAndBroadcastTrade` 调用(两次按"本机签名"),聊天里自然出现两条独立记录,符合实际链上动作。

不会出现"中间状态卡半截":broadcast 要么抛错(失败记录),要么返回 hash(成功记录)。没有第三种结果。

### §4.5 `sessionID` 捕获时机

在 `signAndBroadcastTrade` / `signAndBroadcastTransfer` 函数体**最开始**捕获一份 `let recordSessionID = activeChatSessionID`,然后整个流程(成功 append、失败 append)统一用 `recordSessionID`,**不在 append 时读最新值**。

理由:broadcast 期间用户可能切换历史会话,但 tx 记录应当属于"用户触发签名时所在的那个会话",这样回顾历史会话时操作记录跟意图记录在同一条对话里,语义连贯。

`appendMessage(_:to:)` 已有逻辑会处理 `recordSessionID` 不等于 `activeChatSessionID` 的情况:把消息写到对应历史会话的 `messages` 数组里,不污染当前可见 `chatMessages`。

## §5 测试策略

`CoreSelfTests` 无网络,只测纯函数 + AttributedString 构建。三类用例。

### §5.1 文案格式化

新增 `testBroadcastChatRecordFormat`,覆盖:

- 成功:swap / swapApproval(检查 symbol 嵌入和"授权上链后再来"提示)/ transfer 三个变种各 assert 头部、hash、URL 出现
- 失败:swap / swapApproval / transfer 各 assert 动作标签和对应排查提示

`SampleError`:测试文件内的本地 enum,提供稳定的 `localizedDescription` 给失败用例。

### §5.2 URL 识别 + AttributedString 构建

新增 `testChatBubbleAttributedString`:

- 含一个 URL → URL 区段 link 不为 nil
- 完全无 URL → 所有 run.link == nil
- 含两个不同 URL → 至少识别到 1 个(放宽 assert,因为 `range(of:)` 重复子串限制)

校验整段 `.characters` 字符串等于输入(确保不丢字符)。

### §5.3 不测的部分(明确放弃)

- 不测 `signAndBroadcastTrade` / `signAndBroadcastTransfer` 端到端:`LocalWalletClient` 无协议抽象,无网络测试基础设施。手测已覆盖
- 不测 SwiftUI 渲染:框架行为信赖
- 不测点击 link 是否真的开浏览器:`NSWorkspace.shared.open` 是 OS 标准 API,信赖 OS

### §5.4 现有测试零回归

`ContextChatMessage` 模型不变,所有现有用例不动。

## 非目标 / 后续工作

- 不做"广播交易"卡片视觉(图标 / 颜色标签 / 头像)—— Approach A 路径已放弃
- 不追踪 tx 上链 confirmation 状态 —— 当前只到 "broadcasted",没有 watcher
- 不做点击短 hash 跳浏览器 —— 只有完整 URL 那行可点;短 hash 行只是视觉辅助
- 不动主窗口 `TradeHistorySidebarSection`
- 不实现 pending → confirmed 状态切换
- 不在悬浮窗里加 "查看所有交易历史" 入口(留给主窗口左栏)
