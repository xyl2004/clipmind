# LLM 结构化意图分类器设计

- 日期:2026-06-05
- 状态:Draft,待 user review
- 关联代码:`Sources/AgentWallet/Models/WalletIntent.swift`、`Stores/AppStore.swift`、`Services/LLMClient.swift`

## 背景

ClipMind 当前用 `WalletIntentParser` 这套纯正则规则识别用户在悬浮窗里输入的钱包意图(transfer / swap / ask / unsupported)。规则识别命中率受限于固定关键词("买" / "转" / 等),无法处理"把这个换成 USDT 吧" / "我想 send 一些代币给这个地址" / "这个地址有什么风险" 这类自然表达。

`PRODUCT_REQUIREMENTS.md` 把这个列为 Open Question:

> AI 结构化意图应该由 B.AI 直接返回 JSON,还是先由 App 做规则解析再让 AI 补充解释?

本设计回答这个问题:**用 LLM 作为意图分类主路径,`WalletIntentParser` 退化为 fallback;LLM 只做 NLU 不做文案生成**。

## 已对齐的决策

| 决策点 | 选择 |
|---|---|
| 架构 | LLM 主,规则 fallback |
| Action 词表 | `ask / transfer / swap / unsupported / check_balance / check_token / check_tx / check_address` 共 8 项 |
| 调用结构 | 每轮两次 LLM 调用:先 classify 出 JSON;`action=ask` 再调用现有 `answerAboutContext` |
| JSON 输出强制 | Prompt + 严格解析 + 重试 1 次,不依赖 `response_format` 或 function calling |

## §1 文件结构和职责边界

**新增**

- `Sources/AgentWallet/Models/StructuredIntent.swift` — LLM wire schema 和到 `WalletIntentDraft` 的适配器
- `Sources/AgentWallet/Services/IntentClassifier.swift` — LLM 意图分类器(薄封装,通过 `IntentClassifierBackend` 协议拿原始 JSON 字符串)
- `Sources/AgentWallet/Support/IntentClassifierPrompt.swift` — system prompt 字符串和 few-shot 示例(独立文件方便审阅与迭代)

**改动**

- `Sources/AgentWallet/Services/LLMClient.swift` — 加 `classifyIntent(...)`(实现 `IntentClassifierBackend`)、retry 逻辑、JSON strip
- `Sources/AgentWallet/Stores/AppStore.swift` — 新增 `private let intentClassifier: IntentClassifier`(init 注入,默认 `IntentClassifier(backend: LLMClient())`);`handleWalletIntentIfNeeded` 改成 LLM 优先 + 规则降级;新增 `check_*` 动作分发分支
- `Sources/AgentWallet/Support/CoreSelfTests.swift` — 加 §6 列出的全部新用例

**不动**

- `WalletIntentParser`:签名和行为完全保留,只是从主路径降为 fallback
- 现有 `runResearch / answerAboutContext / buildFloatingTransferPlan / buildFloatingSwapPlan`:适配器把 `StructuredIntent` 翻译成 `WalletIntentDraft` 之后,下游不感知

**数据流**

```
SwiftUI / AppStore
        ↓ user message
IntentClassifier.classify ──(网络/JSON 失败)──→ WalletIntentParser.parse
        ↓ StructuredIntent                                  ↓ WalletIntentDraft
StructuredIntent.toWalletIntentDraft(chain:)                ↓
        ↓ WalletIntentDraft                                 ↓
AppStore 现有 transfer/swap/check_* 分发逻辑 ←──────────────┘
```

## §2 `StructuredIntent` JSON Schema

LLM **只做 NLU,不写文案**。`missing_fields / risk_notes / confirmation_summary` 全部由 App 在适配器里根据规则推导。这样 LLM 没法用幻觉污染风险提示。

**LLM 输出协议(固定 9 字段,缺位用 `""` 或 `null`,不允许新增字段)**

```json
{
  "action": "transfer | swap | check_balance | check_token | check_tx | check_address | ask | unsupported",
  "chain": "ethereum | base | arbitrum | optimism | polygon | unichain | null",
  "target_address": "0x...",
  "target_query": "doge",
  "transaction_hash": "0x...",
  "spend_asset_symbol": "USDC | ETH | \"\"",
  "spend_amount": "20",
  "slippage_percent": 1.0,
  "unsupported_reason": ""
}
```

**字段语义**

| 字段 | 用于哪些 action | 含义 |
|---|---|---|
| `action` | 全部 | 必填,8 选 1 |
| `chain` | transfer/swap/check_balance/check_address/check_token/check_tx | 用 `ChainRegistry.supported` 的 `id`;识别不出留 `null`,App 默认用 `selectedTradeChain` |
| `target_address` | transfer (=recipient)、swap (=代币合约)、check_address/check_token | 0x 开头 40 字符,否则空 |
| `target_query` | swap、check_token、check_address | 用户说的名字或 ticker(如 `doge`、`uni`),只在没拿到合约地址时填 |
| `transaction_hash` | check_tx | 0x 开头 64 字符 |
| `spend_asset_symbol` | transfer、swap | 只允许 `USDC` 或 `ETH`(对应 `chain.defaultSpendToken` 或 `TokenProfile.nativeETH`);非这两个一律留空 |
| `spend_amount` | transfer、swap | 十进制字符串(`20`、`0.5`、`1.5`),不含单位;`5u`/`20U` 在 LLM 内规范化 |
| `slippage_percent` | swap | 用户没说时留 `null`,App 默认 1.0 |
| `unsupported_reason` | unsupported | 一句话中文,例如 `跨链 swap 暂未支持` |

**适配器**:`StructuredIntent.toWalletIntentDraft(chain:fallbackChain:) -> WalletIntentDraft?`

- 返回 `nil` 表示 action 是 `ask` 或 `check_*` 或 `unsupported`,不进 `WalletIntentDraft`(由 dispatch 层处理)
- chain 解析:`ChainRegistry.profile(for: structured.chain) ?? fallbackChain`
- spendAsset:`USDC` → `chain.defaultSpendToken`;`ETH` → `.nativeETH`;空且 swap → `chain.defaultSpendToken`;空且 transfer → 标记 missing
- missing_fields:App 在适配器里重新计算,**不取 LLM 字段**,保持跟规则版完全一致的判定标准
- risk_notes / confirmation_summary:App 按 action 套模板,直接复用现有 `WalletIntentParser` 里的固定中文文案

## §3 Prompt 设计

**System prompt 骨架** (约 1KB,控制 deepseek-v4-flash 延迟)

```
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
```

**Few-shot 示例(6 个,覆盖核心动作和歧义场景)**

| # | selected_context | question | 期望输出要点 |
|---|---|---|---|
| 1 | `0x2222...2222` (address) | `给这个地址转 5 USDC` | `action=transfer`, `target_address=0x2222...`, `spend_asset_symbol=USDC`, `spend_amount=5` |
| 2 | `doge` | `我想买 5u 这个代币` | `action=swap`, `target_query=doge`, `spend_asset_symbol=USDC`, `spend_amount=5` |
| 3 | `0x833589f...02913` (Base USDC) | `用 0.1 ETH 买这个` | `action=swap`, `target_address=0x833589f...`, `spend_asset_symbol=ETH`, `spend_amount=0.1` |
| 4 | `0xA0b8...eB48` | `这个地址安全吗` | `action=check_address`, `target_address=0xA0b8...` |
| 5 | `0xabc...def` (tx hash 64) | `这笔交易做了什么` | `action=check_tx`, `transaction_hash=0xabc...` |
| 6 | `Aave` | `这个项目可以质押吗` | `action=unsupported`, `unsupported_reason=Staking 暂未支持` |

**User 消息模板**

```
[selected_context]
{选中文字,trim 后最多 800 字符,超出截断}

[previous_intent]
{上一轮的 StructuredIntent JSON;首轮省略整段(连同 [previous_intent] 标题一起不发)}

[chain_hint]
{当前 selectedTradeChain.id}

[user_question]
{用户最新一句话}
```

**多轮处理**:previous intent 喂回 LLM。prompt 里强调"如果用户在补字段或修改,merge 后输出完整对象"。**不要**靠 App 自己 merge,因为 LLM 拿到完整上下文,能处理改链 / 改资产 / 改合约,规则版只能补金额。

**重试策略(1 次)**:

- 第一次失败的触发条件:JSON 解析报错 / action 不在枚举 / 任何 0x 字段不是合法长度
- 重试 prompt 追加 `Your previous output was rejected: {具体原因}. Output ONLY a single JSON object matching the schema.`
- 重试仍失败 → 退到 `WalletIntentParser.parse`

**Token 控制**

- 选中文字截断到 800 字符
- `max_tokens: 220`
- `temperature: 0.0`

## §4 `AppStore` 调用流改造

### §4.1 主流程伪代码

```swift
private func handleWalletIntentIfNeeded(
    context: String, question: String, sessionID: ContextChatSession.ID?
) async -> Bool {
    let previousIntent = floatingWalletIntent
    let chain = selectedTradeChain

    let resolved: ResolvedIntent
    do {
        let structured = try await intentClassifier.classify(
            selectedContext: context,
            previousIntent: previousIntent,
            chainHint: chain.id,
            question: question
        )
        resolved = .llm(structured)
    } catch {
        let draft = WalletIntentParser.parse(
            selectedText: context, question: question,
            chain: chain, continuing: previousIntent
        )
        resolved = .rules(draft)
    }

    return await dispatch(resolved, sessionID: sessionID)
}
```

`ResolvedIntent` 是一个内部 enum,只用来在分发层区分来源(用于日志和测试断言),用户感知不到。

### §4.2 Action 分发对照表

| LLM action | App 行为 | 写哪儿 |
|---|---|---|
| `ask` | 返回 `false` → 落到现有 `optionalSurfContext + answerAboutContext` | 聊天流 |
| `transfer` | 适配成 `WalletIntentDraft` → 复用 `buildFloatingTransferPlan` | 悬浮窗 transfer 确认单 |
| `swap` | 适配成 `WalletIntentDraft` → 复用 `buildFloatingSwapPlan`(含 token 候选探测) | 悬浮窗 swap 确认单 |
| `check_balance` | `await refreshSupportedWalletAssets()`,然后 append 一条 assistant 消息汇总 gas 和 token 总值 | 聊天流 |
| `check_address` | `input = target_address`,`selectedKind = .wallet`,`await runResearch()`,再 append assistant 消息 "已在主窗口生成钱包详情" + 一句 LLM 摘要 | 主窗口研究区 + 聊天流摘要 |
| `check_token` | 同上,`selectedKind = .token`,query = `target_address` 或 `target_query` | 同上 |
| `check_tx` | 同上,`selectedKind = .transaction`,query = `transaction_hash` | 同上 |
| `unsupported` | append assistant 消息 = `unsupported_reason`,不改状态 | 聊天流 |

**关键决定**:`check_*` 同时驱动主窗口的研究区(完整 Surf 证据)**和**悬浮聊天的摘要(给用户即时反馈)。主窗口是详情,悬浮窗是回答。

**check_* 退化规则**(分发前过一遍,避免下游崩):

- `check_balance` 但 `localWalletAccount == nil` → append 一条 assistant 消息提示用户先创建本地钱包,不调用 `refreshSupportedWalletAssets()`
- `check_address` 但 `target_address == ""` → 如果 `target_query != ""` 则改走 `check_token`(用 Surf project-detail 路径);否则当 `ask` 处理
- `check_token` 但 `target_address == "" && target_query == ""` → 当 `ask` 处理
- `check_tx` 但 `transaction_hash == ""` → 当 `ask` 处理

### §4.3 状态保留规则

| 触发事件 | `floatingWalletIntent` | `swapTokenCandidates` | `tradePlan` / `transferPlan` |
|---|---|---|---|
| 新 ask 或 check_* | 保留 | 保留 | 保留 |
| 新 transfer/swap | 替换 | 清空(swap 时重新探测) | 清空 |
| unsupported | 保留 | 保留 | 保留 |
| 签名成功 | 清空 | 清空 | 清空 |
| 切换聊天会话 | 清空 | 清空 | 清空 |

**为什么 ask/check_* 不清意图**:用户中途说"这个币安全吗"是在审查候选,不是放弃 swap。保留意图让用户问完直接回去签名。

### §4.4 fallback 路径行为差异

规则 fallback 只能输出 `ask / transfer / swap / unsupported`,**没有 check_***。所以:

- LLM 挂掉后,用户问"这个地址有什么风险"会被规则识别成 `ask` → 走 Q&A,不会自动触发 Surf 研究
- 这是降级,不是错误。用户感知不到分类器不可用,只是少了"自动跳主窗口"的便利

**可观测性**:每次走 fallback 在 `llmErrorMessage` 写一条短日志,不阻断流程。

## §5 错误处理与降级

| 故障类型 | 处置 | 用户感知 |
|---|---|---|
| 网络超时 / 401 / 5xx | 直接退到规则解析 | 无 |
| 缺 B.AI API Key (`LLMClientError.missingAPIKey`) | 退到规则解析 | 无(LLM Q&A 早已有标准提示,不重复) |
| 非法 JSON / markdown 包裹 | strip ```` ```json ```` 后再解析;还失败就重试 1 次,带具体错误回灌 prompt | 无 |
| `action` 不在 8 项枚举 | 重试 1 次,失败退规则 | 无 |
| `target_address` / `transaction_hash` 长度/格式不对 | 重试 1 次,失败退规则 | 无 |
| `chain` 不在 6 链 | 强制改为 `null`,App 用 `selectedTradeChain` 兜底 | 无 |
| `spend_asset_symbol` 不是 `USDC`/`ETH` | 强制改为 `""`,触发 missing_fields | 用户收到"缺支付资产"追问 |
| 429 限流 | 不重试,直接退规则,记一条 `intent classifier rate limited` 到 `llmErrorMessage` | 用户看到一行短提示 |
| 规则 fallback 也失败 | 当作 ask 处理 | 走 Q&A |

**原则**:**永不直接报错给用户**,只降级。LLM 是优化,不是必需路径。

## §6 测试

`CoreSelfTests` 没网络。引入 backend 协议给意图分类器,生产实现调 `LLMClient`,测试实现按预设返回固定 JSON 字符串。

```swift
protocol IntentClassifierBackend {
    func classify(prompt: String, userPayload: String) async throws -> String  // 原始 JSON 字符串
}
```

**新增测试用例(全部在 `CoreSelfTests.swift`,不走网络)**

1. **StructuredIntent JSON 解析** — 8 个 action 各一条 fixture,assert 字段正确
2. **JSON 解析容错** — markdown 包裹 / 末尾多了一段中文解释 / 多余字段 — 都能 strip 出 JSON
3. **JSON 解析拒绝** — action 不在枚举 / target_address 格式错 / chain 越界 — 抛 `IntentClassifierError`
4. **重试触发** — Stub 第一次返回坏 JSON、第二次返回好 JSON → assert 最终拿到结果
5. **fallback 触发** — Stub 两次都返回坏 JSON → assert 落到 `WalletIntentParser.parse` 路径(通过 `ResolvedIntent` 来源标签断言)
6. **适配器** — StructuredIntent → WalletIntentDraft,transfer / swap 两个 action 全字段比对
7. **check_* 不进 WalletIntentDraft** — 适配器对 check_* / ask / unsupported 返回 `nil`
8. **多轮 merge** — 上轮 swap 缺金额,本轮 "20U" 通过 stub 返回完整 swap intent → adapter 出 complete draft

**保留所有现有 `WalletIntentParser` 测试** — fallback 行为不能回归。

## §7 灰度 / 回滚 / 上线顺序

**Feature flag**

- 入口:环境变量 `CLIPMIND_INTENT_BACKEND`
- `auto`(默认 / 未设置)→ 用 LLM,失败退规则
- `rule` → 完全跳过 LLM 分类,只用规则
- `llm` → 跟 `auto` 行为一致(总是先调 LLM),区别只在出错时往 `llmErrorMessage` 写更详细的失败原因,**仍然退规则**保证可用。这个模式用于诊断 LLM 行为,不是"禁止 fallback"
- 读取时机:`AppStore.init`,**一次性读**,不动态切

无 UI 切换。后续真要做 UI 切换时再加到主窗口设置区。

**上线顺序**

1. `StructuredIntent.swift` + 适配器 + 单测(可独立合)
2. `IntentClassifier.swift` + `IntentClassifierBackend` 协议 + stub 单测(可独立合)
3. `LLMClient.classifyIntent(...)` 实现 + retry 逻辑(可独立合,无人调用)
4. `AppStore` 接入 + check_* 分发 + 状态规则(切换主路径,必须配合 flag 才发挥作用)
5. CoreSelfTests 加全部用例;`script/test.sh` 通过即可
6. 默认 `auto` 直接上;有问题用户设 `CLIPMIND_INTENT_BACKEND=rule` 即时关掉

**回滚**:`export CLIPMIND_INTENT_BACKEND=rule` 即可,无需发版。

## 非目标 / 后续工作

- 不在本期实现:UI 设置切换 backend、cost 统计 / 调用计数面板、流式输出回填 ask
- 不引入新链支持(LLM 只能输出现有 6 链)
- 不扩展 transfer/swap 的资产词表(仍只 `USDC` / `ETH`),`spend_asset_symbol` 字段为以后扩展预留
- bridge / approve / stake 等动作明确划入 unsupported,不在本期处理(留给后续 cross-chain 设计)
