# AgentWallet 实现说明

本文档记录当前版本已经完成的工作、运行方式、技术结构和下一步方向。

## 产品方向

当前原型是一个 **EVM 多链 macOS Agent Wallet 上下文助手**。

核心思路是：用户在网页、聊天、区块浏览器或任意页面看到钱包地址、代币合约、交易哈希、项目名称或任意 Web3 文本后，可以选中文字并用快捷键唤醒 AgentWallet 悬浮对话窗。应用会把选中的内容作为上下文带入对话框，用户可以继续问 AI：“这是什么？”“这个地址有什么风险？”“这段话是什么意思？”。

当前版本已经支持上下文问答、EVM 多链信息查询、Uniswap 报价确认单，以及用户点击确认后的本地钱包签名广播。AI 只负责解释和整理交易意图，不接触私钥，也不会自动下单。

## 已完成内容

1. 搭建了 SwiftPM macOS 应用骨架。
2. 使用 SwiftUI 实现了中文界面的主窗口。
3. 增加了菜单栏入口，可以从菜单栏打开应用或查询剪贴板。
4. 接入本地 Surf CLI，作为加密数据查询层。
5. 支持 Ethereum、Base、Arbitrum、OP Mainnet、Polygon、Unichain，并提供“自动”多链模式。
6. 支持识别和查询：
   - 钱包地址
   - 代币合约地址
   - 交易哈希
   - 项目名称
7. 增加了 Uniswap 交易确认区，支持展示链、支付资产、目标代币、金额、滑点、授权需求、Gas 预估和待签名交易。
8. 增加了运行脚本和 Codex Run 配置。
9. 增加了全局快捷键唤醒能力。
10. 增加了读取当前选中文字的能力。
11. 增加了“上下文对话”区域，可以围绕选中的文字继续追问 AI。
12. 接入 B.AI LLM Service，用 deepseek-v4-flash 对选中内容和 Surf 数据生成中文回答。
13. 增加了对话历史：每次读取新的选中文字都会创建一个新的上下文会话。
14. 重做了主界面视觉风格，从原生 macOS 列表/设置页风格改为自定义深色产品界面。
15. API Key 增加进程内缓存，避免每次提问都反复读取 Keychain。
16. 接入 Uniswap Trading API，第一版使用 `/check_approval`、`/quote`、`/swap` 生成同链 swap 确认单。
17. 接入本地钱包第一版：支持创建/导入 EVM 私钥，私钥保存到 macOS Keychain，本机 secp256k1 签名并通过对应链 RPC 广播。

## 数据查询能力

当前 Surf 查询路径如下：

| 输入类型 | Surf 命令 | 作用 |
| --- | --- | --- |
| 钱包地址 | `wallet-detail` | 查询选定链或自动多链的钱包资产、代币、标签、授权 |
| 钱包地址 | `wallet-transfers` | 查询选定链或自动多链的近期转账 |
| 代币合约 | `token-holders` | 查询选定链或自动多链的代币主要持仓地址 |
| 代币合约 | `token-dex-trades` | 查询选定链或自动多链的近期 DEX 交易 |
| 代币合约 | `token-transfers` | 查询选定链或自动多链的近期代币转账 |
| 交易哈希 | `onchain-tx` | 查询选定链或自动多链的交易详情 |
| 项目名称 | `project-detail` | 查询项目概览、代币信息、合约和社交信息 |
| 项目名称 | `search-news` | 查询相关新闻 |

Gas 不再作为默认信息卡片展示；只有交易详情或交易确认单中需要时才展示。

Surf CLI 会从以下路径自动寻找：

- `~/.local/bin/surf`
- `~/.surf/bin/surf`
- `/opt/homebrew/bin/surf`
- `/usr/local/bin/surf`
- `PATH` 中的 `surf`

## 当前界面

当前界面已经改成中文，主要区域包括：

- 左侧栏：网络、数据源、本地签名器状态、示例和对话历史。
- 顶部输入区：选择查询类型、选择链、粘贴内容、查询剪贴板、开始查询。
- 结果区：展示 Surf 返回的结构化数据。
- Surf 命令区：展示本次调用了哪些 Surf 命令。
- 原始 JSON 区：保留原始数据，方便调试。
- 交易确认区：创建/导入本地钱包，生成 Uniswap 报价，用户确认后本机签名广播。
- AI 中文解读区：用 deepseek-v4-flash 将 Surf 数据整理成结论、关键信号、风险提示和下一步建议。
- 上下文对话区：围绕当前选中文字向 AI 提问。
- API Key 设置区：可将 B.AI API Key 保存到 macOS Keychain。
- 对话历史区：每个选中文字对应一个独立会话，可在左侧切换。

视觉风格已经从经典 macOS `NavigationSplitView` / `List` 样式改为自定义产品界面：深色背景、半透明面板、强调色按钮、自绘会话历史和卡片式内容区。技术名保留英文，例如 Ethereum、Base、Surf、DEX、Gas、USDC，避免加密产品里常见名词被翻译后变得不自然。

## 唤醒和选中文字

当前实现了两种读取上下文的方式：

1. 点击页面顶部的“选中文字”按钮。
2. 使用全局快捷键 `Control + Option + W`。

快捷键只负责读取当前选中文字并唤醒 AgentWallet 悬浮对话窗，不会自动开始链上查询，也不会把主窗口拉到前台。读取完成后，选中的内容会出现在“上下文对话”区域，用户可以继续输入问题让 AI 回答。

每次成功读取新的选中文字，应用都会创建一个新的上下文会话。旧会话不会继续混在当前对话框里，而是保留在左侧“对话历史”中。

读取逻辑优先使用 macOS Accessibility API 获取当前焦点应用里的选中文字。如果当前应用不直接暴露选中文本，会回退到模拟 `Command + C`，读取剪贴板内容后再恢复原剪贴板。

首次使用跨应用读取时，macOS 可能要求在系统设置中给 AgentWallet 开启“辅助功能”权限。

## LLM 解读层

当前 LLM 调用使用 B.AI 的 OpenAI-compatible Chat Completions API：

- Base URL：`https://api.b.ai`
- Endpoint：`/v1/chat/completions`
- 模型：`deepseek-v4-flash`
- 鉴权：`Authorization: Bearer <API Key>`

LLM 输入包含：

- 用户查询对象
- 用户选中的上下文文本
- 用户在对话框里输入的问题
- 查询类型
- 当前选定链或自动多链信息
- 可选的 Surf 结构化结果
- 可选的 Surf 原始 JSON

当选中的文本是地址、交易哈希或短项目名时，应用会尝试补充 Surf/EVM 多链数据后再让 AI 回答。普通长文本则直接作为上下文发给 LLM。

Surf 数据解读输出固定为中文，并按以下结构组织：

1. 一句话结论
2. 关键信号
3. 风险提示
4. 下一步建议

为了避免泄露密钥，API Key 不会写入源码或文档。应用会按以下顺序读取：

1. 环境变量 `AGENTWALLET_BAI_API_KEY`
2. 环境变量 `B_AI_API_KEY`
3. macOS Keychain 中的 `AgentWallet.BAIAPIKey`

读取到 API Key 后会缓存在当前进程内。这样同一次应用运行期间后续提问不会反复触发 Keychain 读取，也就不会每次都弹出系统密码确认。

## 本地钱包和安全边界

当前版本已经可以在用户点击确认后本机签名并广播交易，但仍然保持清晰的安全边界：

- 私钥只保存到 macOS Keychain 的 `AgentWallet.LocalPrivateKey`。
- 不保存助记词。
- 不把私钥写入项目目录或日志。
- LLM 不读取私钥，也不直接调用签名函数。
- 每次广播都需要用户点击确认按钮。
- 需要授权的 ERC-20 swap 会先广播授权交易；授权上链后需要重新生成报价再签名兑换。

当前支持的交易路径：

1. 用户输入类似“买 20 USDC 的这个币”或手动填写交易区。
2. AgentWallet 通过 Uniswap API 生成确认单。
3. 用户检查链、支付资产、目标代币、预计收到、Gas、授权需求和风险提示。
4. 用户点击“本机签名授权”或“本机签名兑换”。
5. App 使用 web3swift + secp256k1 在本机签名，通过当前链 RPC 广播。

后续如果扩展真实交易，建议继续保持三层结构：

1. LLM Agent：理解用户意图，解释链上信息。
2. Policy Engine：检查额度、链、资产、滑点、风险规则。
3. Local Signer：只在用户确认后本地签名。

默认 RPC 可通过环境变量覆盖：

| 链 | 环境变量 |
| --- | --- |
| Ethereum | `AGENTWALLET_RPC_ETHEREUM` |
| Base | `AGENTWALLET_RPC_BASE` |
| Arbitrum | `AGENTWALLET_RPC_ARBITRUM` |
| OP Mainnet | `AGENTWALLET_RPC_OPTIMISM` |
| Polygon | `AGENTWALLET_RPC_POLYGON` |
| Unichain | `AGENTWALLET_RPC_UNICHAIN` |

## 文件结构

主要新增文件如下：

```text
Package.swift
README.md
IMPLEMENTATION_NOTES.md
script/build_and_run.sh
.codex/environments/environment.toml
Sources/AgentWallet/App/AgentWalletApp.swift
Sources/AgentWallet/Models/
Sources/AgentWallet/Stores/
Sources/AgentWallet/Services/
Sources/AgentWallet/Support/
Sources/AgentWallet/Views/
```

其中：

- `App/`：应用入口、菜单栏入口、命令菜单。
- `Views/`：SwiftUI 页面组件。
- `Stores/`：应用状态管理。
- `Services/`：Surf CLI 查询服务、Uniswap 报价服务、本地钱包签名服务和结果构建。
- `Models/`：查询类型、查询结果、交易草稿模型。
- `Support/`：JSON 格式化和数据展示辅助方法。

## 运行方式

在当前目录运行：

```bash
./script/build_and_run.sh
```

验证启动：

```bash
./script/build_and_run.sh --verify
```

当前已经验证：

- `swift build` 成功。
- `./script/build_and_run.sh --verify` 成功。
- `AgentWallet` 进程可以正常启动。

## 下一步建议

建议下一步按这个顺序推进：

1. 增加策略检查：最大金额、滑点上限、黑名单、合约风险提示。
2. 给本地钱包增加余额展示、Gas 余额检查和交易历史。
3. 增加更细的交易模拟和失败原因展示，再考虑智能账户或 session key。
