# ClipMind Showcase Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single dark-themed long-scroll landing page in `website/` that showcases ClipMind across two flagship scenarios + a capabilities grid + a Surf/Uniswap/DeepSeek tech callout, deployable to Vercel.

**Architecture:** Next.js 14 App Router with TypeScript, Tailwind for styling, Framer Motion for scroll-triggered animations. Assets prepared by an ffmpeg/sips shell script into `public/`. Single `page.tsx` composes six section components.

**Tech Stack:** Next.js (App Router), TypeScript, Tailwind CSS, Framer Motion, pnpm. macOS-native asset tooling (`ffmpeg`, `sips`).

**Spec:** `docs/superpowers/specs/2026-06-06-showcase-page-design.md`

---

## File Structure

**Create (all under `website/`)**
- `package.json`, `next.config.mjs`, `tailwind.config.ts`, `postcss.config.mjs`, `tsconfig.json` — scaffold
- `scripts/prepare-assets.sh` — one-shot asset pipeline
- `public/` — `hero-demo.mp4`, `hero-demo.webm`, `hero-demo-poster.jpg`, `og-image.png`, `screenshots/*.png`
- `src/app/layout.tsx`, `src/app/page.tsx`, `src/app/globals.css`
- `src/lib/motion-variants.ts`
- `src/components/NavBar.tsx`
- `src/components/HeroSection.tsx`
- `src/components/ScenarioOneSection.tsx`
- `src/components/ScenarioTwoSection.tsx`
- `src/components/CapabilitiesSection.tsx`
- `src/components/TechStackSection.tsx`
- `src/components/CtaSection.tsx`
- `src/components/ui/GlassCard.tsx`
- `src/components/ui/GradientText.tsx`
- `src/components/ui/TagPill.tsx`
- `src/components/ui/BrowserChrome.tsx`

**Modify**
- Root `.gitignore` — add website-specific ignores

**Untouched**
- All Swift sources in `Sources/AgentWallet/`
- Existing top-level config

**No tests:** This is a static showcase page. Verification is `pnpm build` + visual inspection. No unit tests.

---

## Task 1: Scaffold Next.js + Tailwind under `website/`

**Files:**
- Create: `website/package.json`, `next.config.mjs`, `tailwind.config.ts`, `postcss.config.mjs`, `tsconfig.json`, `src/app/layout.tsx`, `src/app/page.tsx`, `src/app/globals.css`
- Modify: root `.gitignore`

- [ ] **Step 1: Create website directory and scaffold Next.js**

From the repository root:

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
pnpm create next-app@latest website \
  --typescript \
  --tailwind \
  --app \
  --src-dir \
  --import-alias "@/*" \
  --eslint \
  --use-pnpm \
  --no-turbopack
```

When the CLI runs, accept the defaults. Wait until `Success! Created website at ...` prints.

- [ ] **Step 2: Install Framer Motion**

```bash
cd website
pnpm add framer-motion
```

- [ ] **Step 3: Update root `.gitignore`**

Open `/Users/xiangyonglin/Documents/AgentWallet/.gitignore` and append at the end:

```
# Website (Next.js)
website/node_modules
website/.next
website/.vercel
website/out
website/.env*.local
```

- [ ] **Step 4: Verify dev server boots**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm dev
```

Expected: `▲ Next.js 14.x.x` and `- Local: http://localhost:3000` print. Open the URL in a browser. The default Next.js page renders.

Stop the dev server with `Ctrl+C`.

- [ ] **Step 5: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/.gitignore website/package.json website/pnpm-lock.yaml \
        website/next.config.mjs website/tailwind.config.ts website/postcss.config.mjs \
        website/tsconfig.json website/.eslintrc.json website/next-env.d.ts \
        website/src .gitignore
git commit -m "$(cat <<'EOF'
Scaffold Next.js + Tailwind showcase page

Creates website/ subdirectory with Next.js 14 App Router + TypeScript +
Tailwind + Framer Motion. Vercel will deploy from this subdirectory by
setting Root Directory to "website" in project settings.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Theme system — colors, fonts, globals

**Files:**
- Modify: `website/tailwind.config.ts`, `website/src/app/layout.tsx`, `website/src/app/globals.css`

- [ ] **Step 1: Configure Tailwind colors**

Replace the entire content of `website/tailwind.config.ts` with:

```ts
import type { Config } from "tailwindcss"

const config: Config = {
  content: ["./src/**/*.{ts,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: "#10b981",
          soft: "#34d399",
          glow: "#22c55e",
        },
        ink: {
          DEFAULT: "#f8fafc",
          muted: "#94a3b8",
          subtle: "#64748b",
        },
        surface: {
          base: "#0a0a0f",
          raised: "#13131a",
          glass: "rgba(255,255,255,0.04)",
          border: "rgba(255,255,255,0.08)",
        },
      },
      fontFamily: {
        sans: ["var(--font-sans)", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "SF Mono", "Menlo", "monospace"],
      },
    },
  },
  plugins: [],
}

export default config
```

- [ ] **Step 2: Replace `globals.css` with theme**

Replace `website/src/app/globals.css` content with:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

html, body {
  background: #0a0a0f;
  color: #f8fafc;
}

body {
  font-family: var(--font-sans), "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

.bg-hero-glow {
  background:
    radial-gradient(60% 60% at 30% 30%, rgba(16, 185, 129, 0.18), transparent 60%),
    radial-gradient(50% 50% at 80% 20%, rgba(139, 92, 246, 0.12), transparent 60%),
    radial-gradient(50% 50% at 50% 100%, rgba(6, 182, 212, 0.10), transparent 60%),
    #0a0a0f;
}

.bg-noise {
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noiseFilter'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noiseFilter)' opacity='0.4'/%3E%3C/svg%3E");
}

.text-gradient-brand {
  background: linear-gradient(135deg, #34d399 0%, #10b981 50%, #06b6d4 100%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
```

- [ ] **Step 3: Replace `layout.tsx` with fonts + MotionConfig + metadata**

Replace `website/src/app/layout.tsx` content with:

```tsx
import type { Metadata } from "next"
import { Inter, JetBrains_Mono } from "next/font/google"
import { MotionConfig } from "framer-motion"
import "./globals.css"

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-sans",
  display: "swap",
})

const mono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  display: "swap",
})

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

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN" className={`${inter.variable} ${mono.variable}`}>
      <body className="bg-surface-base text-ink min-h-screen">
        <MotionConfig reducedMotion="user">{children}</MotionConfig>
      </body>
    </html>
  )
}
```

**Note**: `MotionConfig` must be inside a `"use client"` boundary OR be re-exported via a client wrapper since `layout.tsx` is a server component by default. Wrap it:

Create `website/src/components/motion/MotionProvider.tsx`:

```tsx
"use client"

import { MotionConfig } from "framer-motion"

export function MotionProvider({ children }: { children: React.ReactNode }) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>
}
```

Then replace `MotionConfig` usage in `layout.tsx` with `<MotionProvider>` (re-import accordingly):

```tsx
import { MotionProvider } from "@/components/motion/MotionProvider"
```

And inside `<body>`:

```tsx
<MotionProvider>{children}</MotionProvider>
```

Remove the `MotionConfig` import from `layout.tsx`.

- [ ] **Step 4: Replace `page.tsx` with a placeholder**

Replace `website/src/app/page.tsx` content with:

```tsx
export default function Home() {
  return (
    <main className="min-h-screen bg-hero-glow flex items-center justify-center">
      <h1 className="text-5xl font-semibold text-gradient-brand">ClipMind</h1>
    </main>
  )
}
```

- [ ] **Step 5: Verify dev server renders the theme**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm dev
```

Open `http://localhost:3000`. Expected: dark background with radial green/violet/cyan glow, centered "ClipMind" in gradient text. Stop the server.

- [ ] **Step 6: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/tailwind.config.ts website/src/app/layout.tsx \
        website/src/app/globals.css website/src/app/page.tsx \
        website/src/components/motion/MotionProvider.tsx
git commit -m "$(cat <<'EOF'
Set up theme system: colors, fonts, gradient utilities

Tailwind extends brand/ink/surface palettes. globals.css adds
bg-hero-glow + bg-noise + text-gradient-brand utilities. layout.tsx
mounts Inter + JetBrains_Mono via next/font and wraps body in a
MotionProvider client component that enables prefers-reduced-motion.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Asset preparation script

**Files:**
- Create: `website/scripts/prepare-assets.sh`
- Modify: `website/package.json`

- [ ] **Step 1: Create the script**

Create `website/scripts/prepare-assets.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$HOME/Desktop"
PUBLIC="$ROOT_DIR/public"

command -v ffmpeg >/dev/null || {
  echo "需要先安装 ffmpeg: brew install ffmpeg" >&2
  exit 1
}
command -v sips >/dev/null || {
  echo "需要 sips (macOS 自带)。当前不是 macOS 环境?" >&2
  exit 1
}

SRC_VIDEO="$SRC_DIR/录屏2026-06-06 18.28.43.mov"

if [[ ! -f "$SRC_VIDEO" ]]; then
  echo "未找到源视频: $SRC_VIDEO" >&2
  exit 1
fi

mkdir -p "$PUBLIC/screenshots"

echo "=== Compressing hero video (mp4) ==="
ffmpeg -y -i "$SRC_VIDEO" \
  -vf "scale=1920:-2,fps=30" \
  -c:v libx264 -preset slow -crf 24 \
  -movflags +faststart \
  -an \
  "$PUBLIC/hero-demo.mp4"

echo "=== Compressing hero video (webm) ==="
ffmpeg -y -i "$SRC_VIDEO" \
  -vf "scale=1920:-2,fps=30" \
  -c:v libvpx-vp9 -crf 32 -b:v 0 \
  -an \
  "$PUBLIC/hero-demo.webm"

echo "=== Generating hero poster ==="
ffmpeg -y -i "$SRC_VIDEO" \
  -ss 1 -frames:v 1 \
  -vf "scale=1920:-2" \
  -q:v 3 \
  "$PUBLIC/hero-demo-poster.jpg"

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

echo "=== Compressing screenshots ==="
for pair in "${SHOTS[@]}"; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  if [[ ! -f "$SRC_DIR/$src" ]]; then
    echo "  跳过 (源不存在): $src"
    continue
  fi
  sips -s format png -Z 2400 \
       "$SRC_DIR/$src" \
       --out "$PUBLIC/screenshots/$dst" \
       >/dev/null
  echo "  $src -> screenshots/$dst"
done

echo "=== Generating OG image ==="
if [[ -f "$PUBLIC/screenshots/hero-main-window.png" ]]; then
  sips -c 630 1200 \
       "$PUBLIC/screenshots/hero-main-window.png" \
       --out "$PUBLIC/og-image.png" \
       >/dev/null
fi

echo ""
echo "=== Output ==="
ls -lh "$PUBLIC/hero-demo".{mp4,webm} "$PUBLIC/hero-demo-poster.jpg" "$PUBLIC/og-image.png" 2>/dev/null || true
echo ""
ls -lh "$PUBLIC/screenshots/"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x /Users/xiangyonglin/Documents/AgentWallet/website/scripts/prepare-assets.sh
```

- [ ] **Step 3: Add npm script entry**

Open `website/package.json`. Inside the `"scripts"` object, add this line (next to the existing `dev` / `build` / `start` entries):

```json
"prepare-assets": "bash scripts/prepare-assets.sh"
```

- [ ] **Step 4: Run the script**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm run prepare-assets
```

Expected output ends with file listings under `public/` and `public/screenshots/`. Compressed mp4 should be under ~12 MB. If mp4 exceeds 25 MB, edit the script to use `scale=1280:-2` and rerun.

- [ ] **Step 5: Commit script + assets**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/scripts/prepare-assets.sh website/package.json \
        website/public/hero-demo.mp4 website/public/hero-demo.webm \
        website/public/hero-demo-poster.jpg website/public/og-image.png \
        website/public/screenshots/
git commit -m "$(cat <<'EOF'
Add asset preparation script + compressed media

scripts/prepare-assets.sh compresses the demo recording with ffmpeg
(H.264 mp4 + VP9 webm + first-frame poster) and renames/normalizes
the eight 06-06 screenshots with sips into public/screenshots/. OG
image is cropped from the hero main window screenshot. Script is
idempotent and verifies ffmpeg + macOS sips before running.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Motion variants module

**Files:**
- Create: `website/src/lib/motion-variants.ts`

- [ ] **Step 1: Create the variants module**

Create `website/src/lib/motion-variants.ts`:

```ts
import type { Variants } from "framer-motion"

const easing = [0.16, 1, 0.3, 1] as const

export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 32 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.6, ease: easing } },
}

export const slideInLeft: Variants = {
  hidden: { opacity: 0, x: -40 },
  visible: { opacity: 1, x: 0, transition: { duration: 0.7, ease: easing } },
}

export const slideInRight: Variants = {
  hidden: { opacity: 0, x: 40 },
  visible: { opacity: 1, x: 0, transition: { duration: 0.7, ease: easing } },
}

export const scaleIn: Variants = {
  hidden: { opacity: 0, scale: 0.96 },
  visible: { opacity: 1, scale: 1, transition: { duration: 0.5, ease: "easeOut" } },
}

export function staggerContainer(delay = 0.08): Variants {
  return {
    hidden: {},
    visible: { transition: { staggerChildren: delay } },
  }
}

export const inViewProps = {
  initial: "hidden" as const,
  whileInView: "visible" as const,
  viewport: { once: true, amount: 0.3 } as const,
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/lib/motion-variants.ts
git commit -m "$(cat <<'EOF'
Add framer-motion variant presets

fadeUp / slideInLeft / slideInRight / scaleIn / staggerContainer plus
a shared inViewProps so every scroll-triggered animation triggers
once at 30% viewport intersection with consistent easing.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: UI primitives (GlassCard, GradientText, TagPill, BrowserChrome)

**Files:**
- Create: `website/src/components/ui/GlassCard.tsx`
- Create: `website/src/components/ui/GradientText.tsx`
- Create: `website/src/components/ui/TagPill.tsx`
- Create: `website/src/components/ui/BrowserChrome.tsx`

- [ ] **Step 1: Create GlassCard**

Create `website/src/components/ui/GlassCard.tsx`:

```tsx
import type { ReactNode } from "react"

interface GlassCardProps {
  children: ReactNode
  className?: string
  hover?: boolean
}

export function GlassCard({ children, className = "", hover = true }: GlassCardProps) {
  const hoverClasses = hover
    ? "transition-all duration-300 hover:-translate-y-1 hover:border-brand/40 hover:shadow-[0_12px_40px_rgba(16,185,129,0.15)]"
    : ""

  return (
    <div
      className={`rounded-2xl border border-surface-border bg-surface-glass backdrop-blur-xl shadow-[0_8px_30px_rgba(0,0,0,0.3)] ${hoverClasses} ${className}`}
    >
      {children}
    </div>
  )
}
```

- [ ] **Step 2: Create GradientText**

Create `website/src/components/ui/GradientText.tsx`:

```tsx
import type { ReactNode } from "react"

interface GradientTextProps {
  children: ReactNode
  className?: string
}

export function GradientText({ children, className = "" }: GradientTextProps) {
  return <span className={`text-gradient-brand ${className}`}>{children}</span>
}
```

- [ ] **Step 3: Create TagPill**

Create `website/src/components/ui/TagPill.tsx`:

```tsx
import type { ReactNode } from "react"

interface TagPillProps {
  children: ReactNode
  className?: string
}

export function TagPill({ children, className = "" }: TagPillProps) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border border-brand/30 bg-brand/10 px-3 py-1 text-xs font-medium text-brand-soft ${className}`}
    >
      {children}
    </span>
  )
}
```

- [ ] **Step 4: Create BrowserChrome**

Create `website/src/components/ui/BrowserChrome.tsx`:

```tsx
import type { ReactNode } from "react"

interface BrowserChromeProps {
  children: ReactNode
  className?: string
  label?: string
}

export function BrowserChrome({ children, className = "", label }: BrowserChromeProps) {
  return (
    <div
      className={`overflow-hidden rounded-xl border border-surface-border bg-surface-raised shadow-[0_30px_80px_rgba(0,0,0,0.5)] ${className}`}
    >
      <div className="flex items-center gap-1.5 border-b border-surface-border bg-black/30 px-4 py-3">
        <span className="h-3 w-3 rounded-full bg-red-500/70" />
        <span className="h-3 w-3 rounded-full bg-yellow-500/70" />
        <span className="h-3 w-3 rounded-full bg-green-500/70" />
        {label && (
          <span className="ml-auto text-xs text-ink-subtle">{label}</span>
        )}
      </div>
      <div>{children}</div>
    </div>
  )
}
```

- [ ] **Step 5: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/components/ui
git commit -m "$(cat <<'EOF'
Add UI primitives: GlassCard, GradientText, TagPill, BrowserChrome

Four presentational primitives reused across sections: glass card
with hover lift, gradient text span, brand-tinted pill, and macOS
window chrome that frames screenshots/videos.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: NavBar

**Files:**
- Create: `website/src/components/NavBar.tsx`

- [ ] **Step 1: Create NavBar**

Create `website/src/components/NavBar.tsx`:

```tsx
"use client"

import Link from "next/link"

const ANCHORS = [
  { href: "#scenarios", label: "场景" },
  { href: "#capabilities", label: "能力" },
  { href: "#tech", label: "技术" },
  { href: "#download", label: "下载" },
]

export function NavBar() {
  return (
    <nav className="sticky top-0 z-50 border-b border-surface-border bg-surface-base/60 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <Link href="/" className="flex items-center gap-2 text-lg font-semibold tracking-tight">
          <span className="inline-block h-7 w-7 rounded-md bg-brand" />
          ClipMind
        </Link>
        <ul className="flex items-center gap-6 text-sm text-ink-muted">
          {ANCHORS.map((anchor) => (
            <li key={anchor.href}>
              <Link
                href={anchor.href}
                className="transition-colors hover:text-ink"
              >
                {anchor.label}
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </nav>
  )
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/components/NavBar.tsx
git commit -m "$(cat <<'EOF'
Add NavBar with sticky blur and section anchors

Sticky semi-transparent navbar that blurs the content beneath. Logo
mark + four scroll-link anchors to scenarios / capabilities / tech /
download.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: HeroSection

**Files:**
- Create: `website/src/components/HeroSection.tsx`

- [ ] **Step 1: Create HeroSection**

Create `website/src/components/HeroSection.tsx`:

```tsx
"use client"

import { motion, useMotionValue, useTransform } from "framer-motion"
import { useEffect, useState } from "react"
import { BrowserChrome } from "@/components/ui/BrowserChrome"
import { GradientText } from "@/components/ui/GradientText"
import { TagPill } from "@/components/ui/TagPill"
import { fadeUp, inViewProps, staggerContainer } from "@/lib/motion-variants"

export function HeroSection() {
  const x = useMotionValue(0)
  const y = useMotionValue(0)
  const rotateX = useTransform(y, [-100, 100], [4, -4])
  const rotateY = useTransform(x, [-100, 100], [-4, 4])

  const [parallaxEnabled, setParallaxEnabled] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return
    setParallaxEnabled(window.matchMedia("(pointer: fine)").matches)
  }, [])

  function handleMouseMove(event: React.MouseEvent<HTMLDivElement>) {
    if (!parallaxEnabled) return
    const rect = event.currentTarget.getBoundingClientRect()
    x.set(event.clientX - rect.left - rect.width / 2)
    y.set(event.clientY - rect.top - rect.height / 2)
  }

  return (
    <section
      className="relative min-h-screen overflow-hidden bg-hero-glow pt-20"
      onMouseMove={handleMouseMove}
    >
      <div className="bg-noise pointer-events-none absolute inset-0 opacity-20 mix-blend-overlay" />

      <div className="relative mx-auto grid max-w-6xl items-center gap-12 px-6 py-20 lg:grid-cols-[1.05fr_1fr]">
        <motion.div
          variants={staggerContainer(0.12)}
          initial="hidden"
          animate="visible"
          className="flex flex-col gap-6"
        >
          <motion.div variants={fadeUp}>
            <TagPill>macOS · EVM 多链 · 本地签名</TagPill>
          </motion.div>

          <motion.h1
            variants={fadeUp}
            className="text-5xl font-semibold leading-[1.1] tracking-tight md:text-6xl lg:text-7xl"
          >
            在任何页面，
            <br />
            唤起你的
            <GradientText>区块链 AI 助手</GradientText>
            。
          </motion.h1>

          <motion.p
            variants={fadeUp}
            className="text-lg leading-relaxed text-ink-muted md:text-xl"
          >
            ClipMind 是一款 macOS 悬浮窗钱包助手。
            <br />
            选中文字 · <kbd className="rounded bg-surface-raised px-1.5 py-0.5 font-mono text-sm">⌃⌥W</kbd> 唤起 · 调研、问答、交易一气呵成。
          </motion.p>

          <motion.div variants={fadeUp} className="flex flex-wrap gap-3">
            <a
              href="#download"
              className="inline-flex items-center gap-2 rounded-xl bg-brand px-6 py-3 font-medium text-surface-base transition-colors hover:bg-brand-soft"
            >
              下载 macOS 客户端
            </a>
            <a
              href="https://github.com/xyl2004/clipmind"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-2 rounded-xl border border-surface-border px-6 py-3 font-medium text-ink transition-colors hover:border-brand/40 hover:text-brand-soft"
            >
              GitHub Star
            </a>
          </motion.div>

          <motion.p variants={fadeUp} className="text-sm text-ink-subtle">
            EVM 多链 · 本地签名 · 私钥仅存 Keychain
          </motion.p>
        </motion.div>

        <motion.div
          {...inViewProps}
          variants={{
            hidden: { opacity: 0, scale: 1.05 },
            visible: { opacity: 1, scale: 1, transition: { duration: 0.7, ease: [0.16, 1, 0.3, 1] } },
          }}
          style={{ rotateX, rotateY, transformPerspective: 1200 }}
          className="relative"
        >
          <BrowserChrome label="ClipMind · Live demo">
            <video
              src="/hero-demo.mp4"
              poster="/hero-demo-poster.jpg"
              autoPlay
              muted
              loop
              playsInline
              className="block w-full"
            />
          </BrowserChrome>
        </motion.div>
      </div>
    </section>
  )
}
```

- [ ] **Step 2: Wire HeroSection into page**

Replace `website/src/app/page.tsx` content with:

```tsx
import { HeroSection } from "@/components/HeroSection"
import { NavBar } from "@/components/NavBar"

export default function Home() {
  return (
    <>
      <NavBar />
      <HeroSection />
    </>
  )
}
```

- [ ] **Step 3: Verify visually**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm dev
```

Open `http://localhost:3000`. Expected:
- Sticky top navbar with logo + 4 anchors
- Below it: dark background with glow, headline with gradient on "区块链 AI 助手"
- Right side: macOS-style window chrome wrapping the demo video, video autoplays muted, loops
- Move mouse over hero → subtle 4° tilt on video

Stop the server.

- [ ] **Step 4: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/components/HeroSection.tsx website/src/app/page.tsx
git commit -m "$(cat <<'EOF'
Add HeroSection with hero video + headline + parallax tilt

Two-column hero: stagger-faded headline / sub / CTAs on the left, demo
video wrapped in BrowserChrome on the right with a 4° mouse-tilt
parallax (only on pointer:fine devices). Wires HeroSection + NavBar
into the page.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: ScenarioOneSection

**Files:**
- Create: `website/src/components/ScenarioOneSection.tsx`
- Modify: `website/src/app/page.tsx`

- [ ] **Step 1: Create ScenarioOneSection**

Create `website/src/components/ScenarioOneSection.tsx`:

```tsx
"use client"

import Image from "next/image"
import { motion } from "framer-motion"
import { BrowserChrome } from "@/components/ui/BrowserChrome"
import { TagPill } from "@/components/ui/TagPill"
import {
  fadeUp,
  inViewProps,
  slideInLeft,
  staggerContainer,
} from "@/lib/motion-variants"

const BULLETS = [
  "项目背景、代币信息、合约地址 一站式",
  "Surf 实时链上数据,自动多链查询",
  "AI 中文解读:结论 / 关键信号 / 风险 / 下一步",
]

export function ScenarioOneSection() {
  return (
    <section id="scenarios" className="relative bg-surface-base px-6 py-20 md:py-32">
      <div className="mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-[1.2fr_1fr]">
        <motion.div {...inViewProps} variants={slideInLeft}>
          <BrowserChrome label="X (Twitter) · Virtuals Protocol">
            <Image
              src="/screenshots/scenario1-overlay.png"
              alt="ClipMind 悬浮窗叠在 X 上,实时调研 Virtuals Protocol"
              width={2400}
              height={1500}
              className="block h-auto w-full"
              priority
            />
          </BrowserChrome>
        </motion.div>

        <motion.div
          {...inViewProps}
          variants={staggerContainer(0.12)}
          className="flex flex-col gap-6"
        >
          <motion.div variants={fadeUp}>
            <TagPill>场景一</TagPill>
          </motion.div>

          <motion.h2
            variants={fadeUp}
            className="text-3xl font-semibold tracking-tight md:text-5xl"
          >
            朋友推了一个项目，
            <br />
            你没听过 — 怎么办？
          </motion.h2>

          <motion.div variants={fadeUp} className="space-y-4 text-ink-muted">
            <p className="text-base leading-relaxed md:text-lg">
              <span className="text-ink-subtle">旧方式:</span>
              <br />
              退出聊天 → 打开 X / 浏览器 → 多源拼凑 → 信息仍不完整。
            </p>
            <p className="text-base leading-relaxed md:text-lg">
              <span className="text-brand-soft">ClipMind 方式:</span>
              <br />
              在任何页面选中项目名 → <kbd className="rounded bg-surface-raised px-1.5 py-0.5 font-mono text-sm">⌃⌥W</kbd> → 立刻拿到结构化调研。
            </p>
          </motion.div>

          <motion.ul variants={fadeUp} className="flex flex-col gap-3 text-ink">
            {BULLETS.map((bullet) => (
              <li key={bullet} className="flex items-start gap-3">
                <span className="mt-2 inline-block h-1.5 w-1.5 flex-shrink-0 rounded-full bg-brand" />
                <span className="text-base leading-relaxed md:text-lg">{bullet}</span>
              </li>
            ))}
          </motion.ul>
        </motion.div>
      </div>
    </section>
  )
}
```

- [ ] **Step 2: Wire into page**

Replace `website/src/app/page.tsx`:

```tsx
import { HeroSection } from "@/components/HeroSection"
import { NavBar } from "@/components/NavBar"
import { ScenarioOneSection } from "@/components/ScenarioOneSection"

export default function Home() {
  return (
    <>
      <NavBar />
      <HeroSection />
      <ScenarioOneSection />
    </>
  )
}
```

- [ ] **Step 3: Verify visually**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm dev
```

Scroll past hero → scenario one slides in from left with screenshot in browser chrome, right side stagger fades the title, the旧/ClipMind comparison and three bullets.

Stop the server.

- [ ] **Step 4: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/components/ScenarioOneSection.tsx website/src/app/page.tsx
git commit -m "$(cat <<'EOF'
Add ScenarioOneSection: project research

Two-column scenario block showing the overlay screenshot on the left
(slideInLeft on viewport entry) and the headline + old-way / new-way
contrast + three benefit bullets on the right (stagger fade-up).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: ScenarioTwoSection

**Files:**
- Create: `website/src/components/ScenarioTwoSection.tsx`
- Modify: `website/src/app/page.tsx`

- [ ] **Step 1: Create ScenarioTwoSection**

Create `website/src/components/ScenarioTwoSection.tsx`:

```tsx
"use client"

import Image from "next/image"
import { motion } from "framer-motion"
import { BrowserChrome } from "@/components/ui/BrowserChrome"
import { TagPill } from "@/components/ui/TagPill"
import {
  fadeUp,
  inViewProps,
  slideInRight,
  staggerContainer,
} from "@/lib/motion-variants"

interface StepProps {
  index: number
  title: string
  body: React.ReactNode
  image?: string
  alt?: string
}

function Placeholder({ label }: { label: string }) {
  return (
    <div className="flex aspect-[16/10] items-center justify-center rounded-xl border border-dashed border-surface-border bg-gradient-to-br from-surface-raised to-surface-base">
      <span className="text-sm text-ink-subtle">{label}</span>
    </div>
  )
}

const STEPS: StepProps[] = [
  {
    index: 1,
    title: "选中代币名或合约地址,问 \"这是什么 / 安全吗\"",
    body: (
      <>
        AI 给出结构化解读 + Surf 链上证据。
        <br />
        合约风险、持仓集中度、近期 DEX 交易 一次看完。
      </>
    ),
    image: "/screenshots/scenario2-intent.png",
    alt: "悬浮窗中自然语言意图识别",
  },
  {
    index: 2,
    title: "接着问 \"用 0.001 ETH 买这个\"",
    body: (
      <>
        AI 把自然语言变结构化交易意图。
        <br />
        Uniswap 报价 + 候选合约自动甄别 + 风险评分。
      </>
    ),
  },
  {
    index: 3,
    title: "检查确认单 → 输入收款地址后 4 位 → 本机签名",
    body: (
      <>
        钱包私钥从未离开 macOS Keychain。
        <br />
        交易哈希直接显示在聊天里,点击跳浏览器。
      </>
    ),
  },
]

function StepRow({ step }: { step: StepProps }) {
  return (
    <motion.div
      {...inViewProps}
      variants={slideInRight}
      className="grid items-center gap-8 lg:grid-cols-[1fr_1.3fr]"
    >
      <div className="flex flex-col gap-4">
        <span className="inline-flex h-12 w-12 items-center justify-center rounded-xl border border-brand/30 bg-brand/10 text-xl font-semibold text-brand-soft">
          {step.index}
        </span>
        <h3 className="text-xl font-medium leading-snug md:text-2xl">{step.title}</h3>
        <p className="text-base leading-relaxed text-ink-muted md:text-lg">{step.body}</p>
      </div>

      <div>
        {step.image ? (
          <BrowserChrome>
            <Image
              src={step.image}
              alt={step.alt ?? ""}
              width={2400}
              height={1500}
              className="block h-auto w-full"
            />
          </BrowserChrome>
        ) : (
          <Placeholder label="Coming soon — 等你截图" />
        )}
      </div>
    </motion.div>
  )
}

export function ScenarioTwoSection() {
  return (
    <section className="relative bg-surface-base px-6 py-20 md:py-32">
      <div className="mx-auto max-w-6xl">
        <motion.div
          {...inViewProps}
          variants={staggerContainer(0.1)}
          className="mb-16 flex flex-col gap-4 text-center"
        >
          <motion.div variants={fadeUp} className="mx-auto">
            <TagPill>场景二</TagPill>
          </motion.div>
          <motion.h2
            variants={fadeUp}
            className="text-3xl font-semibold tracking-tight md:text-5xl"
          >
            朋友给你按头了一个代币 —
            <br />
            <span className="text-gradient-brand">直接边问边买。</span>
          </motion.h2>
        </motion.div>

        <div className="flex flex-col gap-20">
          {STEPS.map((step) => (
            <StepRow key={step.index} step={step} />
          ))}
        </div>
      </div>
    </section>
  )
}
```

- [ ] **Step 2: Wire into page**

Update `website/src/app/page.tsx`:

```tsx
import { HeroSection } from "@/components/HeroSection"
import { NavBar } from "@/components/NavBar"
import { ScenarioOneSection } from "@/components/ScenarioOneSection"
import { ScenarioTwoSection } from "@/components/ScenarioTwoSection"

export default function Home() {
  return (
    <>
      <NavBar />
      <HeroSection />
      <ScenarioOneSection />
      <ScenarioTwoSection />
    </>
  )
}
```

- [ ] **Step 3: Verify visually**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm dev
```

Scroll past scenario one → scenario two has center title then three rows. Step 1 has a screenshot, steps 2 and 3 show dashed "Coming soon" placeholders.

- [ ] **Step 4: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/components/ScenarioTwoSection.tsx website/src/app/page.tsx
git commit -m "$(cat <<'EOF'
Add ScenarioTwoSection: research-then-trade timeline

Three-step row layout for the token research + Uniswap buy flow. Step
one uses scenario2-intent.png; steps two and three carry "Coming soon"
placeholders matching the screenshot aspect ratio so layout stays put
when the user drops in the real screenshots later.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: CapabilitiesSection

**Files:**
- Create: `website/src/components/CapabilitiesSection.tsx`
- Modify: `website/src/app/page.tsx`

- [ ] **Step 1: Create CapabilitiesSection**

Create `website/src/components/CapabilitiesSection.tsx`:

```tsx
"use client"

import Image from "next/image"
import { motion } from "framer-motion"
import { GlassCard } from "@/components/ui/GlassCard"
import { TagPill } from "@/components/ui/TagPill"
import {
  fadeUp,
  inViewProps,
  staggerContainer,
} from "@/lib/motion-variants"

interface Capability {
  title: string
  body: string
  image?: string
}

const CAPABILITIES: Capability[] = [
  {
    title: "项目调研",
    body: "项目背景 / 代币 / 合约 / 社交 / 新闻 一站式",
    image: "/screenshots/module-research.png",
  },
  {
    title: "合约 & 地址安全",
    body: "链上标签、授权、持仓集中度、隐含风险评分",
    image: "/screenshots/module-risk.png",
  },
  {
    title: "代币交易",
    body: "Uniswap 报价 + 候选甄别 + 滑点 / Gas 风险检查",
  },
  {
    title: "转账",
    body: "自然语言 → 结构化转账单 → 本机签名 → 链上证据",
  },
]

function CapabilityCard({ capability }: { capability: Capability }) {
  return (
    <motion.div variants={fadeUp} className="h-full">
      <GlassCard className="flex h-full flex-col gap-4 p-6">
        <div className="aspect-[4/3] overflow-hidden rounded-lg border border-surface-border bg-surface-raised">
          {capability.image ? (
            <Image
              src={capability.image}
              alt=""
              width={1600}
              height={1200}
              className="block h-full w-full object-cover"
            />
          ) : (
            <div className="flex h-full items-center justify-center text-xs text-ink-subtle">
              Coming soon
            </div>
          )}
        </div>
        <h3 className="text-xl font-medium">{capability.title}</h3>
        <p className="text-sm leading-relaxed text-ink-muted">{capability.body}</p>
      </GlassCard>
    </motion.div>
  )
}

export function CapabilitiesSection() {
  return (
    <section id="capabilities" className="relative bg-surface-base px-6 py-20 md:py-32">
      <div className="mx-auto max-w-6xl">
        <motion.div
          {...inViewProps}
          variants={staggerContainer(0.08)}
          className="mb-16 flex flex-col gap-4 text-center"
        >
          <motion.div variants={fadeUp} className="mx-auto">
            <TagPill>能力矩阵</TagPill>
          </motion.div>
          <motion.h2
            variants={fadeUp}
            className="text-3xl font-semibold tracking-tight md:text-5xl"
          >
            一个悬浮窗，
            <br />
            把四件事按头给你做了。
          </motion.h2>
        </motion.div>

        <motion.div
          {...inViewProps}
          variants={staggerContainer(0.08)}
          className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-4"
        >
          {CAPABILITIES.map((capability) => (
            <CapabilityCard key={capability.title} capability={capability} />
          ))}
        </motion.div>
      </div>
    </section>
  )
}
```

- [ ] **Step 2: Wire into page**

Update `website/src/app/page.tsx`:

```tsx
import { CapabilitiesSection } from "@/components/CapabilitiesSection"
import { HeroSection } from "@/components/HeroSection"
import { NavBar } from "@/components/NavBar"
import { ScenarioOneSection } from "@/components/ScenarioOneSection"
import { ScenarioTwoSection } from "@/components/ScenarioTwoSection"

export default function Home() {
  return (
    <>
      <NavBar />
      <HeroSection />
      <ScenarioOneSection />
      <ScenarioTwoSection />
      <CapabilitiesSection />
    </>
  )
}
```

- [ ] **Step 3: Verify visually**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm dev
```

After scenario two: heading "一个悬浮窗" + four glass cards in a 4-column grid (collapses to 2x2 on tablet, 1 column on mobile). Hover on a card → it floats up 1px with brand-tinted border.

- [ ] **Step 4: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/components/CapabilitiesSection.tsx website/src/app/page.tsx
git commit -m "$(cat <<'EOF'
Add CapabilitiesSection: 4-up glass card grid

Responsive grid of GlassCard tiles for project research, contract
safety, token swap, and transfer. Stagger fade-up on entry, hover
lift + brand border. Two tiles carry image placeholders for the
trade screenshots the user will provide later.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: TechStackSection

**Files:**
- Create: `website/src/components/TechStackSection.tsx`
- Modify: `website/src/app/page.tsx`

**Constraint:** Only mention "DeepSeek v4 API" for the AI engine. Never reference b.ai or any proxy.

- [ ] **Step 1: Create TechStackSection**

Create `website/src/components/TechStackSection.tsx`:

```tsx
"use client"

import { motion } from "framer-motion"
import { GlassCard } from "@/components/ui/GlassCard"
import { TagPill } from "@/components/ui/TagPill"
import {
  fadeUp,
  inViewProps,
  slideInRight,
  staggerContainer,
} from "@/lib/motion-variants"

interface TechBlock {
  badge: string
  title: string
  subtitle: string
  bullets: string[]
  accent: string
}

const BLOCKS: TechBlock[] = [
  {
    badge: "01",
    title: "Surf 投研引擎",
    subtitle: "通过 Surf 提供的 skill 调用，直连多链数据。",
    bullets: [
      "多链并发查询(Ethereum / Base / Arbitrum / OP / Polygon / Unichain)",
      "钱包资产、代币持仓、DEX 交易、合约标签",
      "项目详情与新闻聚合",
    ],
    accent: "from-emerald-500/30 to-emerald-500/0",
  },
  {
    badge: "02",
    title: "Uniswap 交易引擎",
    subtitle: "接入 Uniswap 官方 Trading API，从报价到 swap 全流程。",
    bullets: [
      "BEST_PRICE 路由 + 多版本协议(V2 / V3 / V4)",
      "候选合约风险评分(隐含价偏离、池流动性、价格冲击)",
      "ERC-20 授权与原生 ETH 路径自动甄别",
    ],
    accent: "from-violet-500/30 to-violet-500/0",
  },
  {
    badge: "03",
    title: "DeepSeek v4 AI 引擎",
    subtitle: "通过 DeepSeek v4 API 实现自然语言理解。",
    bullets: [
      "自然语言意图分类(transfer / swap / 调研 / 风险查询)",
      "中文结构化解读(结论 / 关键信号 / 风险 / 下一步)",
      "多轮上下文与字段补全",
    ],
    accent: "from-cyan-500/30 to-cyan-500/0",
  },
]

function TechRow({ block }: { block: TechBlock }) {
  return (
    <motion.div {...inViewProps} variants={slideInRight}>
      <GlassCard className="relative overflow-hidden p-8">
        <div className={`pointer-events-none absolute -left-20 top-1/2 h-72 w-72 -translate-y-1/2 rounded-full bg-gradient-radial ${block.accent} blur-3xl`} />
        <div className="relative grid items-start gap-6 lg:grid-cols-[120px_1fr]">
          <span className="font-mono text-3xl font-semibold text-ink-subtle">{block.badge}</span>
          <div className="flex flex-col gap-4">
            <h3 className="text-2xl font-semibold tracking-tight md:text-3xl">
              {block.title}
            </h3>
            <p className="text-base text-ink-muted md:text-lg">{block.subtitle}</p>
            <ul className="flex flex-col gap-2 text-ink-muted">
              {block.bullets.map((bullet) => (
                <li key={bullet} className="flex items-start gap-2">
                  <span className="mt-2 inline-block h-1 w-1 flex-shrink-0 rounded-full bg-brand" />
                  <span className="text-sm md:text-base">{bullet}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </GlassCard>
    </motion.div>
  )
}

export function TechStackSection() {
  return (
    <section id="tech" className="relative bg-surface-base px-6 py-20 md:py-32">
      <div className="mx-auto max-w-6xl">
        <motion.div
          {...inViewProps}
          variants={staggerContainer(0.08)}
          className="mb-16 flex flex-col gap-4 text-center"
        >
          <motion.div variants={fadeUp} className="mx-auto">
            <TagPill>技术架构</TagPill>
          </motion.div>
          <motion.h2
            variants={fadeUp}
            className="text-3xl font-semibold tracking-tight md:text-5xl"
          >
            投研、交易、AI —
            <br />
            <span className="text-gradient-brand">三个引擎拼出 ClipMind。</span>
          </motion.h2>
        </motion.div>

        <div className="flex flex-col gap-6">
          {BLOCKS.map((block) => (
            <TechRow key={block.badge} block={block} />
          ))}
        </div>
      </div>
    </section>
  )
}
```

- [ ] **Step 2: Wire into page**

Update `website/src/app/page.tsx`:

```tsx
import { CapabilitiesSection } from "@/components/CapabilitiesSection"
import { HeroSection } from "@/components/HeroSection"
import { NavBar } from "@/components/NavBar"
import { ScenarioOneSection } from "@/components/ScenarioOneSection"
import { ScenarioTwoSection } from "@/components/ScenarioTwoSection"
import { TechStackSection } from "@/components/TechStackSection"

export default function Home() {
  return (
    <>
      <NavBar />
      <HeroSection />
      <ScenarioOneSection />
      <ScenarioTwoSection />
      <CapabilitiesSection />
      <TechStackSection />
    </>
  )
}
```

- [ ] **Step 3: Verify visually + grep for forbidden term**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm dev
```

Expected: three tech blocks slide in from the right with green/violet/cyan radial bleeds on the left side.

Verify "b.ai" never appears anywhere in `src/`:

```bash
grep -r "b\.ai\|B\.AI\|b-ai" src/ && echo "FORBIDDEN TERM FOUND" || echo "ok"
```

Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/components/TechStackSection.tsx website/src/app/page.tsx
git commit -m "$(cat <<'EOF'
Add TechStackSection: Surf, Uniswap, DeepSeek v4

Three stacked GlassCard rows describing the investigative, trading,
and AI engines with brand-tinted radial bleeds. The AI block names
DeepSeek v4 directly and only — the proxy provider is never named
on the marketing page.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: CtaSection

**Files:**
- Create: `website/src/components/CtaSection.tsx`
- Modify: `website/src/app/page.tsx`

- [ ] **Step 1: Create CtaSection**

Create `website/src/components/CtaSection.tsx`:

```tsx
"use client"

import { motion } from "framer-motion"
import { fadeUp, inViewProps, staggerContainer } from "@/lib/motion-variants"

export function CtaSection() {
  return (
    <section id="download" className="relative overflow-hidden bg-hero-glow px-6 py-32 md:py-40">
      <div className="bg-noise pointer-events-none absolute inset-0 opacity-10 mix-blend-overlay" />
      <motion.div
        {...inViewProps}
        variants={staggerContainer(0.1)}
        className="relative mx-auto flex max-w-3xl flex-col items-center gap-8 text-center"
      >
        <motion.h2
          variants={fadeUp}
          className="text-4xl font-semibold tracking-tight md:text-6xl"
        >
          ClipMind
        </motion.h2>
        <motion.p
          variants={fadeUp}
          className="text-lg text-ink-muted md:text-xl"
        >
          你的区块链 AI 助手 · 选中即调研，对话即交易。
        </motion.p>
        <motion.div variants={fadeUp} className="flex flex-wrap items-center justify-center gap-4">
          <a
            href="https://github.com/xyl2004/clipmind/releases"
            className="inline-flex items-center gap-2 rounded-xl bg-brand px-8 py-4 text-lg font-medium text-surface-base transition-colors hover:bg-brand-soft"
          >
            下载 macOS 客户端
          </a>
          <a
            href="https://github.com/xyl2004/clipmind"
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 rounded-xl border border-surface-border px-8 py-4 text-lg font-medium text-ink transition-colors hover:border-brand/40 hover:text-brand-soft"
          >
            GitHub Star
          </a>
        </motion.div>
        <motion.div variants={fadeUp} className="mt-4 flex flex-col gap-2 text-sm text-ink-subtle">
          <p>本地钱包 · 私钥仅存 macOS Keychain · 永不离开你的设备</p>
          <p>所有交易需要本机签名 · AI 仅负责理解，绝不接触私钥</p>
        </motion.div>
      </motion.div>
    </section>
  )
}
```

- [ ] **Step 2: Wire into page**

Update `website/src/app/page.tsx`:

```tsx
import { CapabilitiesSection } from "@/components/CapabilitiesSection"
import { CtaSection } from "@/components/CtaSection"
import { HeroSection } from "@/components/HeroSection"
import { NavBar } from "@/components/NavBar"
import { ScenarioOneSection } from "@/components/ScenarioOneSection"
import { ScenarioTwoSection } from "@/components/ScenarioTwoSection"
import { TechStackSection } from "@/components/TechStackSection"

export default function Home() {
  return (
    <>
      <NavBar />
      <HeroSection />
      <ScenarioOneSection />
      <ScenarioTwoSection />
      <CapabilitiesSection />
      <TechStackSection />
      <CtaSection />
    </>
  )
}
```

- [ ] **Step 3: Verify visually**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm dev
```

Page bottom: centered ClipMind name, tagline, two big buttons, safety microcopy. Glow background carries through.

- [ ] **Step 4: Commit**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git add website/src/components/CtaSection.tsx website/src/app/page.tsx
git commit -m "$(cat <<'EOF'
Add CtaSection: closing call to action

Centered name + tagline + two large CTAs (download / GitHub) wrapped
in the hero glow background. Safety microcopy at the bottom reiterates
local-only keys and that AI never touches the private key material.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Production build verification + push

**Files:** no source changes; verification + final push.

- [ ] **Step 1: Run production build**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm build
```

Expected: `✓ Compiled successfully` and a summary table showing `/` as `○ Static`. Fix any TypeScript errors that surface (most likely missing imports — copy them in from the relevant component file).

- [ ] **Step 2: Smoke test production output**

```bash
cd /Users/xiangyonglin/Documents/AgentWallet/website
pnpm start
```

Open `http://localhost:3000`. Verify all six sections render in order, video autoplays, screenshots load, anchors scroll correctly when clicking the navbar links, hover states work on capability cards. Stop with `Ctrl+C`.

- [ ] **Step 3: Push to clipmind/main**

Per the saved push preference (`clipmind` remote):

```bash
cd /Users/xiangyonglin/Documents/AgentWallet
git push clipmind codex/floating-chat-history:main
```

Expected: fast-forward push succeeds with `<old>..<new>  codex/floating-chat-history -> main`.

- [ ] **Step 4: Connect Vercel and deploy**

This step happens in the Vercel web UI, not in code:

1. Go to https://vercel.com/new
2. "Import Git Repository" → select `xyl2004/clipmind`
3. Project settings:
   - **Root Directory**: `website`
   - **Framework Preset**: Next.js (auto-detected)
   - **Build Command**: `pnpm build` (auto)
   - **Output Directory**: `.next` (auto)
4. Click "Deploy"

After the first deploy succeeds, copy the production URL. Future pushes to the default branch auto-redeploy.

- [ ] **Step 5: Final verification**

Open the Vercel production URL. Repeat the visual smoke from Step 2 on the live site. If video LCP feels slow, drop to `scale=1280:-2` in `scripts/prepare-assets.sh`, rerun, commit, re-push.

No commit step needed unless Step 1 or 5 surfaced issues to fix.

---

## Self-Review Notes

**Spec coverage**
- §1 file structure → Tasks 1, 4, 5, and per-section tasks for components
- §2 page sections (Hero / Scenario1 / Scenario2 / Capabilities / TechStack / CTA) → Tasks 7-12
- §3 theme system (colors / fonts / gradients / variants / GlassCard / animation) → Tasks 2, 4, 5
- §4 asset preparation script → Task 3
- §5 deployment + metadata → Task 13 + metadata covered in Task 2 `layout.tsx`

**Type consistency**
- `motion-variants.ts` exports `fadeUp / slideInLeft / slideInRight / scaleIn / staggerContainer / inViewProps` — used consistently across Tasks 7-12.
- `GlassCard / GradientText / TagPill / BrowserChrome` signatures defined in Task 5 — used consistently in Tasks 7-12.
- File paths use `@/components/...` and `@/lib/...` import alias consistently (configured in Task 1 scaffold).

**No placeholders detected.** Placeholders mentioned in source code (`"Coming soon — 等你截图"`) are intentional UI affordances per spec §4.4, not plan placeholders.
