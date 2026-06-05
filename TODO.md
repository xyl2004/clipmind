# LLM Structured Intent — TODO

跟踪用。代码细节在 [`docs/superpowers/plans/2026-06-05-llm-structured-intent.md`](./docs/superpowers/plans/2026-06-05-llm-structured-intent.md) 对应 Task。

## Task 1 — `StructuredIntent` 类型与 8 个 action
- [x] 写测试 `testStructuredIntentTypes`(构造 + allCases)
- [x] 跑 `./script/test.sh`,确认编译失败
- [x] 创建 `Sources/AgentWallet/Models/StructuredIntent.swift`(enum + struct + `empty()`)
- [x] 跑 `./script/test.sh`,确认 PASS
- [x] commit

## Task 2 — JSON 严格解析
- [ ] 追加 3 条 fixture 测试(transfer / swap / check_tx)
- [ ] 跑 `./script/test.sh`,失败于 `no member 'decode'`
- [ ] 实现 `StructuredIntent.decode(raw:)` + `StructuredIntentDecodeError`
- [ ] 跑 `./script/test.sh`,PASS
- [ ] commit

## Task 3 — JSON 容错(strip markdown / 末尾文字)
- [ ] 加 2 条容错 fixture
- [ ] 跑测试,失败
- [ ] 加 `extractFirstJSONObject(from:)`,改 `decode` 先 strip
- [ ] 跑测试,PASS
- [ ] commit

## Task 4 — JSON 拒绝非法字段
- [ ] 加 5 条 `expectThrows`(unknown action / 坏 address / 坏 hash / 越界 chain / 非 JSON)
- [ ] 跑测试,PASS(实现已就位,这步只锁契约)
- [ ] commit

## Task 5 — 适配器 `toWalletIntentDraft`
- [ ] 新增 `testStructuredIntentAdapter`(transfer / swap / missing_fields / ask/check_*/unsupported 返 nil)
- [ ] 跑测试,失败于 `no member 'toWalletIntentDraft'`
- [ ] 实现适配器 + `resolveSpendAsset` 私有助手
- [ ] 跑测试,PASS
- [ ] commit

## Task 6 — `IntentClassifier` + `IntentClassifierBackend` + Stub
- [ ] 新增 `testIntentClassifierStub`(快乐路径)
- [ ] 跑测试,失败
- [ ] 创建 `Sources/AgentWallet/Services/IntentClassifier.swift`(协议 + struct + retry + StubBackend + IntentClassifierError + 占位 IntentClassifierPrompt)
- [ ] 跑测试,PASS
- [ ] commit

## Task 7 — 重试 1 次
- [ ] 追加测试:坏 JSON → 好 JSON,assert callCount=2 且重试 payload 含 "Your previous output was rejected"
- [ ] 跑测试,PASS(实现已在 Task 6)
- [ ] commit

## Task 8 — 重试用尽抛 `IntentClassifierError`
- [ ] 追加测试:两次坏 JSON,assert 抛 `IntentClassifierError`,callCount=2
- [ ] 跑测试,PASS
- [ ] commit

## Task 9 — 真 `IntentClassifierPrompt`
- [ ] 新增 `testIntentClassifierPrompt`(action 词覆盖 / chain 覆盖 / 首轮无 previous_intent 块 / 续轮有 / 超长截断)
- [ ] 跑测试,失败(占位 systemPrompt 为空)
- [ ] 创建 `Sources/AgentWallet/Support/IntentClassifierPrompt.swift`(system + 6 个 few-shot + payload builder + truncate + serializePreviousIntent)
- [ ] 从 `IntentClassifier.swift` 删除占位 `IntentClassifierPrompt`
- [ ] 跑测试,PASS
- [ ] commit

## Task 10 — `LLMClient.classifyChat` 生产实现
- [ ] 在 `LLMClient` 加 `classifyChat(system:user:)` 调 `sendChat(temperature: 0.0, maxTokens: 220)`
- [ ] 加 `extension LLMClient: IntentClassifierBackend {}`
- [ ] 跑 `swift build`,PASS
- [ ] commit(本任务无单测,集成靠 Task 15 手动)

## Task 11 — `AppStore` 注入 + flag
- [ ] 加 `IntentBackendMode` enum(auto/rule/llm + `fromEnvironment`)
- [ ] `AppStore.init` 加 `intentClassifier` 和 `intentBackendMode` 可注入参数(默认值不破坏现有调用方)
- [ ] 跑 `swift build`,PASS
- [ ] commit(无行为变化)

## Task 12 — `handleWalletIntentIfNeeded` LLM-first(transfer/swap/ask/unsupported)
- [ ] 新增 `testAppStoreIntentDispatch`(LLM 成功 → swap intent / fallback → rule transfer / rule mode 不调 LLM)
- [ ] 跑测试,失败
- [ ] 重写 `handleWalletIntentIfNeeded` + 加 `dispatchStructuredIntent` 和 `dispatchRuleDraft`,check_* 暂时退化到 ask
- [ ] 跑测试,PASS
- [ ] commit

## Task 13 — `check_*` 分发 + 退化规则
- [ ] 新增 `testAppStoreCheckActions`(check_balance 无钱包 / check_address 空地址有 query / check_tx 空 hash)
- [ ] 跑测试,失败
- [ ] 实现 `handleCheckBalance` + `buildBalanceSummary` + `handleCheckAddress` + `handleCheckToken` + `handleCheckTx` + `runCheckResearch`
- [ ] 替换 `dispatchStructuredIntent` 的 check_* 分支
- [ ] 跑测试,PASS
- [ ] commit

## Task 14 — 状态保留(ask/check_*/unsupported 不清意图)
- [ ] 新增 `testAppStoreIntentStatePreservation`(swap → ask → unsupported,assert 意图 id 不变)
- [ ] 跑测试
- [ ] 如有失败,审计 `dispatchStructuredIntent` 的 .unsupported / check_* 分支,确保不调 `resetFloatingWalletAction`
- [ ] 跑测试,PASS
- [ ] commit(改了源 commit 源 + 测试;没改源只 commit 测试)

## Task 15 — 全量验证
- [ ] `./script/test.sh` 全 PASS
- [ ] `./script/build_and_run.sh --verify`
- [ ] 手测 LLM 路径(`CLIPMIND_INTENT_BACKEND=auto` + B.AI key):Aave + "可以质押吗" → unsupported 中文消息;地址 + "安全吗" → runResearch 触发
- [ ] 手测 rule 路径(`CLIPMIND_INTENT_BACKEND=rule`):地址 + "转 5 USDC" → 确认单;地址 + "有什么风险" → 普通 Q&A
- [ ] 更新 `IMPLEMENTATION_NOTES.md` 第 19 条
- [ ] commit
