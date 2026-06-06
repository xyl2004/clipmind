# ClipMind

**在任何页面，唤起你的区块链 AI 助手。**

产品展示页：[https://clipmind-showcase.vercel.app](https://clipmind-showcase.vercel.app)

ClipMind 是一款 macOS 悬浮窗钱包助手。

选中文字 · `⌃⌥W` 唤起 · 调研、问答、交易一气呵成。

它解决的是用户在 Web3 场景里最常遇到的那一刻：看到一个地址、合约、交易哈希、项目名或代币名，但还不知道它是什么、是否安全、下一步该不该操作。

用户只需要在任意 macOS 页面里选中文字，按下 `⌃⌥W`，ClipMind 会打开一个全局悬浮窗。AI 可以基于选中内容做项目调研、代币分析、合约和地址安全检查，并在用户明确确认后准备转账或交易。最后一步签名始终由用户手动完成，私钥只保存在本地 macOS Keychain，不会暴露给 AI。

## 核心问题

Web3 用户经常在聊天软件、X、区块浏览器、项目文档、行情页和交易工具之间来回切换。真正困难的不只是签名，而是签名前的理解和判断：

- 这个地址是什么？
- 这个合约是不是正确的代币合约？
- 这笔交易发生了什么？
- 这个项目是做什么的？
- 朋友让我买这个币，我能不能先查清楚？
- 这个地址能不能收款，是否存在风险？

传统钱包通常从 dApp 发起交易请求后才出现。ClipMind 往前走一步，让用户在当前页面直接唤起区块链 AI 助手，从已经看到并选中的文字开始。

## 产品思路

ClipMind 把一段选中文本变成一个 AI 引导的钱包工作流：

```text
选中 Web3 文本
-> 按 ⌃⌥W 唤起 ClipMind
-> 用自然语言提问或下达操作意图
-> 需要时调用 Surf 获取链上证据和项目信息
-> 识别意图：问答、风险检查、转账、交易
-> 生成可读的交易或转账确认单
-> 校验链、余额、Gas、报价新鲜度和风险提示
-> 用户确认
-> 本地钱包签名
```

AI 负责理解、解释和准备操作，钱包只在用户明确确认后签名。

## 典型场景

### 1. 选中项目名，快速调研

用户在聊天、X 或网页里看到一个项目名，例如：

```text
Virtuals
Morpho
```

选中后可以直接问：

```text
这个项目是做什么的？
我可以怎么参与这个项目？
这个项目最近有什么风险？
```

ClipMind 会结合当前选中内容、Surf 数据、链上信息和相关新闻，给出结构化中文解释。

### 2. 选中地址或合约，检查风险

用户可以选中钱包地址、代币合约或交易哈希，然后问：

```text
这个地址安全吗？
这个合约是什么？
这笔交易发生了什么？
```

ClipMind 会尝试识别链、资产、合约、钱包行为和风险信号，避免用户把合约地址误当成收款地址，或在不了解对象的情况下交互。

### 3. 选中收款地址，准备转账

```text
给这个地址转 5 USDC
```

ClipMind 会解析转账意图，生成确认单，检查地址、链、余额和 Gas。用户确认后，交易才会由本地钱包签名。

### 4. 选中代币，准备交易

```text
用 0.001 ETH 买这个
```

ClipMind 会把自然语言转换成结构化交易意图，调用 Uniswap 报价，展示预计收到、Gas、授权需求、报价新鲜度和风险提示。最后一步必须由用户手动签名，防止 AI 幻觉或误判直接执行。

## 为什么不同

- **选中文字优先**：工作流从用户正在看的内容开始，而不是从一个空白钱包表单开始。
- **AI 原生意图层**：自然语言可以被转换成结构化钱包操作，并保留规则兜底。
- **先证据，后执行**：在准备交易前，先通过 Surf 和链上数据补充上下文。
- **本地签名边界**：私钥只保存在 macOS Keychain，AI 不读取私钥，也不能直接调用签名。
- **全局悬浮窗**：用户不用离开当前页面，就能完成调研、追问、确认和执行。

## 当前能力

- 通过 `Control + Option + W` 唤起 macOS 全局悬浮窗。
- 根据选中文本创建独立对话和历史记录。
- 通过 Surf CLI 查询钱包、代币、交易、合约和项目信息。
- 使用 DeepSeek V4 API 生成中文解释和意图分类。
- 支持 LLM 优先的结构化意图识别，并提供规则兜底。
- 支持余额、地址、代币、交易和合约的只读检查。
- 支持用户确认后的转账和交易规划。
- 支持 Ethereum、Base、Arbitrum、OP Mainnet、Polygon 等 EVM 链的 Uniswap 报价。
- 支持本地 EVM 钱包创建和导入。
- 私钥存储在 macOS Keychain。
- 所有签名都必须经过用户明确确认。
- 内置核心自测，覆盖意图解析、交易校验、链配置、钱包资产和本地钱包导出检查。

## 安全模型

ClipMind 把 AI 输出视为草稿，而不是最终权限。

- AI 不能读取私钥。
- AI 不能直接调用签名函数。
- AI 不能在没有用户确认的情况下广播交易。
- 交易计划必须通过校验后才能进入签名步骤。
- 报价过期、地址无效、链不匹配、字段缺失、余额不足或 Gas 异常都会阻止执行。
- 私钥导出需要单独的本地确认。

## 技术栈

- SwiftUI macOS 应用
- Swift Package Manager
- web3swift + secp256k1 本地签名
- macOS Keychain
- Surf CLI 链上调研
- DeepSeek V4 API 中文解释和意图识别
- Uniswap API 报价和交易构建
- Next.js + Vercel 产品展示页

## 环境要求

- macOS 14+
- Xcode 15+，Swift 5.9 或更新版本
- Surf CLI
- 选中文本捕获需要授予 macOS 辅助功能权限
- 可选：DeepSeek V4 API key，用于 AI 解释和意图分类
- 可选：Uniswap API key，用于报价和交易构建

安装 Surf：

```bash
curl -fsSL https://downloads.asksurf.ai/cli/releases/install.sh | sh
surf sync
```

常用环境变量：

```bash
CLIPMIND_UNISWAP_API_KEY=...
CLIPMIND_INTENT_BACKEND=auto   # auto, llm, rule
CLIPMIND_RPC_ETHEREUM=...
CLIPMIND_RPC_BASE=...
CLIPMIND_RPC_ARBITRUM=...
CLIPMIND_RPC_OPTIMISM=...
CLIPMIND_RPC_POLYGON=...
```

## 运行

```bash
./script/build_and_run.sh
```

常用参数：

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

## 测试

```bash
./script/test.sh
```

这个脚本会执行：

```bash
swift run ClipMind --self-test-core
```

自测路径不会发起真实网络调用，并使用隔离的测试 Keychain 服务。它是当前仓库里主要的自动化测试入口。

## 产品状态

ClipMind 目前是一个实验性比赛版本。它展示了一种 selection-first AI wallet 工作流：AI 帮助用户理解、查证和准备操作，但最终签名必须留在本地，并由用户明确确认。
