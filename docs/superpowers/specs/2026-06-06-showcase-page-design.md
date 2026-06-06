# ClipMind 产品展示页设计

- 日期:2026-06-06
- 状态:Draft,待 user review
- 用途:比赛展示用的产品落地页,Vercel 公网托管
- 关联资产:`~/Desktop/录屏2026-06-06 18.28.43.mov` + 8 张 06-06 截图

## 背景

ClipMind 当前没有产品落地页,比赛展示需要一个"打开链接就能看明白产品做什么"的中文落地页。产品宣传噱头围绕两个真实场景(项目调研 / 代币购买与转账)展开,技术亮点是 Surf 投研 + Uniswap 交易 + DeepSeek v4 AI(不提中转的 b.ai)。

## 已对齐的决策

| 决策点 | 选择 |
|---|---|
| 部署 | Vercel 公网 URL |
| 仓库结构 | monorepo:在现有仓库下加 `website/` 子目录 |
| 技术栈 | Next.js App Router + Tailwind CSS + Framer Motion |
| 语言 | 中文为主,技术词保留英文(EVM / Base / Uniswap / DeepSeek) |
| 视觉调性 | 深色 + 渐变光晕 + glassmorphism + 长滚动叙事 + emerald 绿品牌色 |
| 视频 | 录屏 ffmpeg 压缩后做 Hero 自动 loop |
| 测试 | 不写自动化,本地 + Vercel 预览肉眼验证 |

## §1 项目结构

仓库结构:在现有 `/Users/xiangyonglin/Documents/AgentWallet/` 根目录下加 `website/` 子目录,跟 Swift 源码并列。Vercel Project Settings 里 Root Directory 设成 `website`,部署时只跑 Next.js。

```
website/
├── package.json
├── next.config.mjs
├── tailwind.config.ts
├── postcss.config.mjs
├── tsconfig.json
├── scripts/
│   └── prepare-assets.sh          # 视频压缩 + 截图重命名/压缩,一次跑完
├── public/
│   ├── hero-demo.mp4              # 录屏压缩 H.264
│   ├── hero-demo.webm             # 录屏压缩 VP9(可选)
│   ├── hero-demo-poster.jpg       # video 加载前静帧
│   ├── og-image.png               # 社交分享卡
│   └── screenshots/
│       ├── hero-main-window.png
│       ├── scenario1-overlay.png
│       ├── scenario1-alt.png
│       ├── scenario1-zec-detail.png
│       ├── scenario2-intent.png
│       ├── module-research.png
│       ├── module-risk.png
│       └── module-floating.png
└── src/
    ├── app/
    │   ├── layout.tsx             # 字体、metadata、MotionConfig 全局
    │   ├── page.tsx               # 单页:6 个 section 顺序拼装
    │   └── globals.css            # Tailwind base + CSS 变量
    ├── components/
    │   ├── NavBar.tsx
    │   ├── HeroSection.tsx
    │   ├── ScenarioOneSection.tsx
    │   ├── ScenarioTwoSection.tsx
    │   ├── CapabilitiesSection.tsx
    │   ├── TechStackSection.tsx
    │   ├── CtaSection.tsx
    │   ├── motion/
    │   │   ├── FadeIn.tsx
    │   │   ├── ParallaxFloat.tsx
    │   │   └── StaggerList.tsx
    │   └── ui/
    │       ├── GlassCard.tsx
    │       ├── GradientText.tsx
    │       ├── TagPill.tsx
    │       └── BrowserChrome.tsx
    └── lib/
        └── motion-variants.ts     # 全站 framer-motion variants
```

仓库根 `.gitignore` 追加:`website/node_modules`、`website/.next`、`website/.vercel`。

## §2 页面 6 个 Section

整页 dark theme,emerald-500 品牌色,顺序如下。所有 section 用 `max-w-6xl mx-auto px-6 py-32 md:py-20` 包容。

### Section 1 — Hero

**布局**:左文案 + 右 video。背景 radial 渐变叠噪点。

**主视觉**:`<video src="/hero-demo.mp4" autoplay muted loop playsinline poster="/hero-demo-poster.jpg" />`,外层 `BrowserChrome` 装裱。

**文案**:

- Headline:在任何页面，唤起你的区块链 AI 助手。
- Sub:ClipMind 是一款 macOS 悬浮窗钱包助手。选中文字 · ⌃⌥W 唤起 · 调研、问答、交易一气呵成。
- CTA 主:下载 macOS 客户端
- CTA 次:GitHub Star
- 信任小字:EVM 多链 · 本地签名 · 私钥仅存 Keychain

**动画**:Headline 字符 stagger fade-in;sub 滞后 200ms;video 区域 scale 1.05 → 1 + opacity 0 → 1;鼠标移动时 video 容器轻微视差(`pointer:fine` 设备启用)。

### Section 2 — 场景一:项目调研

**布局**:左 60% 截图,右 40% 文案。

**主视觉**:`scenario1-overlay.png`(悬浮窗叠在 X / Virtuals Protocol 推文上),BrowserChrome 装裱。

**文案骨架**:

```
小标题:场景一
Headline:朋友推了一个项目，你没听过，怎么办？

旧方式:
退出聊天 → 打开 X / 浏览器 → 多源拼凑 → 信息仍不完整

ClipMind 方式:
在任何页面选中项目名 → ⌃⌥W → 立刻拿到结构化调研
· 项目背景、代币信息、合约地址
· Surf 实时链上数据
· AI 中文解读：结论 / 关键信号 / 风险 / 下一步
```

**动画**:scroll 进入视口,左截图 slideInLeft -40px,右文案 staggerContainer 三句话 fadeUp。

### Section 3 — 场景二:代币调研与交易

**布局**:三步纵向 timeline,每步左 caption 右截图。

**三步截图**:
1. `scenario2-intent.png`(自然语言意图识别)
2. **占位**(待补:swap 候选列表)
3. **占位**(待补:swap 确认单 + tx 记录)

**文案骨架**:

```
小标题:场景二
Headline:朋友给你按头了一个代币 — 直接边问边买。

第一步:选中代币名或合约地址，问"这是什么 / 安全吗"
       → AI 给出结构化解读 + Surf 链上证据

第二步:接着问"用 0.001 ETH 买这个"
       → AI 把自然语言变结构化交易意图
       → Uniswap 报价 + 候选合约自动甄别 + 风险评分

第三步:检查确认单 → 输入收款地址后 4 位 → 本机签名
       → 钱包私钥从未离开 macOS Keychain
       → 交易哈希直接显示在聊天里，点击跳浏览器
```

**动画**:三步各自从右 -40px slideInRight,延迟错开。

### Section 4 — 能力矩阵

**布局**:4 列卡片网格,响应式:`grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6`。每张是 `GlassCard`。

**4 张卡片**:

| # | 标题 | 一句话 | 配图 |
|---|---|---|---|
| 1 | 项目调研 | 项目背景 / 代币 / 合约 / 社交 / 新闻 一站式 | `module-research.png` |
| 2 | 合约 & 地址安全 | 链上标签、授权、持仓集中度、隐含风险评分 | `module-risk.png` |
| 3 | 代币交易 | Uniswap 报价 + 候选甄别 + 滑点 / Gas 风险检查 | (占位) |
| 4 | 转账 | 自然语言 → 结构化转账单 → 本机签名 → 链上证据 | (占位) |

**动画**:`StaggerList` 4 卡错时 80ms slide-up + fade-in。hover 上浮 4px + 边框由 `border-surface-border` 变 `border-brand/40`。

### Section 5 — 技术架构

**布局**:三横排,每排左侧 icon 占位 + 右侧描述。

**三块**:

```
1. Surf 投研引擎
   通过 Surf 提供的 skill 调用，直连多链数据。
   · 多链并发查询(Ethereum / Base / Arbitrum / OP / Polygon / Unichain)
   · 钱包资产、代币持仓、DEX 交易、合约标签
   · 项目详情与新闻聚合

2. Uniswap 交易引擎
   接入 Uniswap 官方 Trading API，从报价到 swap 全流程。
   · BEST_PRICE 路由 + 多版本协议(V2 / V3 / V4)
   · 候选合约风险评分(隐含价偏离、池流动性、价格冲击)
   · ERC-20 授权与原生 ETH 路径自动甄别

3. DeepSeek v4 AI 引擎
   通过 DeepSeek v4 API 实现自然语言理解。
   · 自然语言意图分类(transfer / swap / 调研 / 风险查询)
   · 中文结构化解读(结论 / 关键信号 / 风险 / 下一步)
   · 多轮上下文与字段补全
```

**关键约束**:绝不提到 b.ai。文案里只说"DeepSeek v4 API"。

**动画**:三块从右 -30px slideInRight。

### Section 6 — CTA

**布局**:居中段落 + 两个大按钮 + 底部小字。

**文案**:

```
ClipMind
你的区块链 AI 助手 · 选中即调研，对话即交易。

[下载 macOS 客户端]   [GitHub Star]

本地钱包 · 私钥仅存 macOS Keychain · 永不离开你的设备
所有交易需要本机签名 · AI 仅负责理解，绝不接触私钥
```

### NavBar

顶部 `sticky` 半透明 + scroll 模糊。左 logo "ClipMind",右四锚点:`场景` / `能力` / `技术` / `下载`。

## §3 主题系统

### §3.1 字体

`Inter`(英文)+ `JetBrains_Mono`(等宽)走 `next/font/google`。中文走系统字体栈,不引网络字体。

```css
--font-sans: var(--font-sans), "PingFang SC", "Hiragino Sans GB",
             "Microsoft YaHei", system-ui, sans-serif;
--font-mono: var(--font-mono), "SF Mono", "Menlo", monospace;
```

### §3.2 颜色

Tailwind `theme.extend.colors`:

```ts
brand: {
  DEFAULT: "#10b981",
  soft:    "#34d399",
  glow:    "#22c55e",
},
ink: {
  DEFAULT: "#f8fafc",
  muted:   "#94a3b8",
  subtle:  "#64748b",
},
surface: {
  base:    "#0a0a0f",
  raised:  "#13131a",
  glass:   "rgba(255,255,255,0.04)",
  border:  "rgba(255,255,255,0.08)",
},
```

**渐变 utilities**(`globals.css`):

```css
.bg-hero-glow {
  background:
    radial-gradient(60% 60% at 30% 30%, rgba(16,185,129,0.18), transparent 60%),
    radial-gradient(50% 50% at 80% 20%, rgba(139,92,246,0.12), transparent 60%),
    radial-gradient(50% 50% at 50% 100%, rgba(6,182,212,0.10), transparent 60%),
    #0a0a0f;
}

.text-gradient-brand {
  background: linear-gradient(135deg, #34d399 0%, #10b981 50%, #06b6d4 100%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
```

### §3.3 排版

| 元素 | class |
|---|---|
| Hero headline | `text-5xl md:text-6xl lg:text-7xl font-semibold tracking-tight` |
| Section h2 | `text-3xl md:text-5xl font-semibold tracking-tight` |
| 卡片标题 | `text-xl font-medium` |
| 正文 | `text-base md:text-lg leading-relaxed text-ink-muted` |
| Section padding | `py-20 md:py-32` |
| 内容容器 | `max-w-6xl mx-auto px-6` |

### §3.4 GlassCard 组件

```tsx
<div className="
  rounded-2xl border border-surface-border
  bg-surface-glass backdrop-blur-xl
  shadow-[0_8px_30px_rgba(0,0,0,0.3)]
  transition-all duration-300
  hover:-translate-y-1
  hover:border-brand/40
  hover:shadow-[0_12px_40px_rgba(16,185,129,0.15)]
">
```

### §3.5 动画

`src/lib/motion-variants.ts`:

```ts
export const fadeUp = {
  hidden: { opacity: 0, y: 32 },
  visible: { opacity: 1, y: 0,
    transition: { duration: 0.6, ease: [0.16, 1, 0.3, 1] } },
}

export const slideInLeft = {
  hidden: { opacity: 0, x: -40 },
  visible: { opacity: 1, x: 0,
    transition: { duration: 0.7, ease: [0.16, 1, 0.3, 1] } },
}

export const slideInRight = {
  hidden: { opacity: 0, x: 40 },
  visible: { opacity: 1, x: 0,
    transition: { duration: 0.7, ease: [0.16, 1, 0.3, 1] } },
}

export const scaleIn = {
  hidden: { opacity: 0, scale: 0.96 },
  visible: { opacity: 1, scale: 1,
    transition: { duration: 0.5, ease: "easeOut" } },
}

export const staggerContainer = (delay = 0.08) => ({
  visible: { transition: { staggerChildren: delay } },
})
```

触发统一用 `whileInView={{ once: true, amount: 0.3 }}`(进入视口 30% 触发,只触发一次)。

**Hero 鼠标视差**:`useMotionValue` + `useTransform` 实现 4° tilt,仅 `@media (pointer:fine)` 启用。

### §3.6 减少动画偏好

`layout.tsx` 用 `<MotionConfig reducedMotion="user">` 包整个 body,系统级关闭动画时 transition → 0。

## §4 资产准备

`website/scripts/prepare-assets.sh` 一次跑完所有资产处理:视频压缩、截图重命名压缩、OG 卡生成。脚本可重复跑(`set -euo pipefail`)。

**依赖**:`ffmpeg`(视频压缩)和 `sips`(截图压缩,macOS 自带)。`ffmpeg` 用 `brew install ffmpeg` 安装,脚本开头先 `command -v ffmpeg >/dev/null || { echo "需要先安装 ffmpeg: brew install ffmpeg"; exit 1; }`。

### §4.1 视频压缩

源:`~/Desktop/录屏2026-06-06 18.28.43.mov`(121MB / 1550p / 60fps / 93s)

```bash
SRC_VIDEO="$HOME/Desktop/录屏2026-06-06 18.28.43.mov"

ffmpeg -y -i "$SRC_VIDEO" \
  -vf "scale=1920:-2,fps=30" \
  -c:v libx264 -preset slow -crf 24 \
  -movflags +faststart \
  -an \
  "$PUBLIC/hero-demo.mp4"

ffmpeg -y -i "$SRC_VIDEO" \
  -vf "scale=1920:-2,fps=30" \
  -c:v libvpx-vp9 -crf 32 -b:v 0 \
  -an \
  "$PUBLIC/hero-demo.webm"

ffmpeg -y -i "$SRC_VIDEO" \
  -ss 1 -frames:v 1 \
  -vf "scale=1920:-2" \
  -q:v 3 \
  "$PUBLIC/hero-demo-poster.jpg"
```

参数注释:`scale=1920:-2` 限宽 1920px 高度自适应偶数;`fps=30` 砍半帧;`-crf 24` H.264 网络甜区;`-crf 32` VP9 等效画质;`-movflags +faststart` moov atom 前置可流式;`-an` 移除音轨。预期 mp4 ≈ 7-10MB,webm ≈ 4-6MB。如果还偏大,降到 `scale=1280:-2`。

### §4.2 截图处理

```bash
SHOTS=(
  "截屏2026-06-06 14.31.09.png:hero-main-window.png"
  "截屏2026-06-06 14.29.52.png:scenario1-overlay.png"
  "截屏2026-06-06 10.52.08.png:scenario1-alt.png"
  "截屏2026-06-06 11.30.04.png:scenario1-zec-detail.png"
  "截屏2026-06-06 10.52.12.png:scenario2-intent.png"
  "截屏2026-06-06 14.31.35.png:module-research.png"
  "截屏2026-06-06 14.30.47.png:module-risk.png"
  "截屏2026-06-06 14.30.36.png:module-floating.png"
)

mkdir -p "$PUBLIC/screenshots"

for pair in "${SHOTS[@]}"; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  sips -s format png -Z 2400 \
       "$HOME/Desktop/$src" \
       --out "$PUBLIC/screenshots/$dst" \
       >/dev/null
done
```

用 macOS 内置 `sips` 不引入额外依赖。`-Z 2400` 限最长边 2400px。`next/image` 后续会自动生成 webp/avif + srcset。

### §4.3 OG image

```bash
sips -c 630 1200 \
     "$PUBLIC/screenshots/hero-main-window.png" \
     --out "$PUBLIC/og-image.png" >/dev/null
```

第一版凑合用,后期手画更精致的替换。

### §4.4 缺失资产占位

§2 §3 标记的占位(swap 候选列表 / swap 确认单 / tx 记录可点击 URL)实施时用占位 div 顶着,布局不漂移。占位规则:相同尺寸渐变盒 + 中央 "Coming soon" 灰字 + 虚线边框。用户后续抽空截图丢桌面,跑 `prepare-assets.sh` 自动合进去。

### §4.5 脚本入口

`website/package.json` 加:

```json
"scripts": {
  "prepare-assets": "bash scripts/prepare-assets.sh"
}
```

## §5 部署 + Metadata

### §5.1 Vercel

仓库 push 到 GitHub → Vercel 控制台 "New Project" → 选这个仓库 → **Root Directory 改成 `website`** → Deploy。后续推默认分支自动 redeploy。

### §5.2 Metadata

`src/app/layout.tsx`:

```tsx
export const metadata: Metadata = {
  title: "ClipMind — 在任何页面，唤起你的区块链 AI 助手",
  description:
    "macOS 悬浮窗钱包助手。选中文字 · ⌃⌥W 唤起 · 项目调研 / 代币交易 / 转账 一气呵成。",
  openGraph: {
    title: "ClipMind",
    description: "在任何页面，唤起你的区块链 AI 助手",
    images: ["/og-image.png"],
  },
}
```

### §5.3 测试

不写自动化测试。`pnpm dev` 本地看 → push → Vercel 预览 URL 再看一眼 → 满意就完事。

## 非目标 / 后续工作

- 不做多语言切换(只中文,英文术语保留)
- 不做暗 / 亮主题切换(只 dark)
- 不接 analytics / 不接 newsletter / 不做 contact form
- 不做 blog / docs / changelog 子页
- 不做下载追踪 / 链接 attribution
- 缺失三张截图(swap 候选 / swap 确认单 / tx 记录)实施时用占位,后期补
- Logo 设计后期再做,先用纯文字 "ClipMind"
