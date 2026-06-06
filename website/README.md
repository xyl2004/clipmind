# ClipMind Showcase

这是 ClipMind 的产品展示页，部署在 Vercel：

[https://clipmind-showcase.vercel.app](https://clipmind-showcase.vercel.app)

核心表达：

```text
在任何页面，
唤起你的区块链 AI 助手。

ClipMind 是一款 macOS 悬浮窗钱包助手。
选中文字 · ⌃⌥W 唤起 · 调研、问答、交易一气呵成。
```

页面用于展示 ClipMind 的核心定位、真实使用场景、能力矩阵、技术架构和未来愿景。它不是 Next.js 默认模板，而是面向 GitHub、比赛展示和产品介绍的官网。

## 页面内容

- 首屏：在任何页面唤起区块链 AI 助手，展示 macOS 悬浮窗钱包定位和产品演示视频。
- 场景一：朋友推荐一个项目时，选中文字后直接调研。
- 场景二：从代币解释、候选合约、Uniswap 确认单到本机签名。
- 能力矩阵：项目调研、合约和地址安全、代币交易、转账。
- 技术架构：Surf 投研引擎、Uniswap 交易引擎、DeepSeek v4 AI 引擎。
- CTA：下载 macOS 客户端和 GitHub 仓库入口。
- 未来愿景：x402、智能 AI 理财、多 DEX 多链和多 Agent 协作。

## 本地开发

```bash
pnpm install
pnpm dev
```

打开：

```text
http://localhost:3000
```

## 构建检查

```bash
pnpm lint
pnpm build
```

## 部署

当前目录已经关联到 Vercel 项目 `clipmind-showcase`。

部署 production：

```bash
pnpm exec vercel deploy --prod --yes
```

## 资源目录

主要图片和视频资源放在：

```text
website/public/
website/public/screenshots/
```

如果替换截图，建议使用新的文件名，避免线上图片缓存继续命中旧资源。
