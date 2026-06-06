"use client"

import Image from "next/image"
import { motion } from "framer-motion"
import { BrowserChrome } from "@/components/ui/BrowserChrome"
import { TagPill } from "@/components/ui/TagPill"
import { Zoomable } from "@/components/ui/Zoomable"
import {
  fadeUp,
  inViewProps,
  slideInRight,
  staggerContainer,
} from "@/lib/motion-variants"

interface StepImage {
  src: string
  alt: string
  label?: string
}

interface StepProps {
  index: number
  title: string
  body: React.ReactNode
  images: StepImage[]
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
    images: [
      {
        src: "/screenshots/scenario2-step1-chat.png",
        alt: "悬浮窗中选中 USDC 合约地址询问'这是什么相关的',AI 给出结构化解读",
        label: "ClipMind · 上下文问答",
      },
      {
        src: "/screenshots/scenario2-step1-explain.png",
        alt: "AI 中文解读卡:结论 / 关键信号 / 风险提示 / 下一步建议",
        label: "AI 中文解读",
      },
    ],
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
    images: [
      {
        src: "/screenshots/scenario2-step2-candidates.png",
        alt: "悬浮窗钱包动作卡显示 Base 上的 morpho 候选合约 + Uniswap 候选列表",
        label: "钱包动作 · Uniswap 候选合约",
      },
    ],
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
    images: [
      {
        src: "/screenshots/scenario2-step3-confirm.png",
        alt: "Uniswap 确认单显示支付、预计收到、Gas、授权、安全检查和本机签名兑换按钮",
        label: "Uniswap 确认单 · 本机签名兑换",
      },
    ],
  },
]

function StepImageBlock({ image }: { image: StepImage }) {
  return (
    <Zoomable label={`放大查看:${image.label ?? image.alt}`}>
      <BrowserChrome label={image.label}>
        <Image
          src={image.src}
          alt={image.alt}
          width={2400}
          height={1500}
          className="block h-auto w-full"
        />
      </BrowserChrome>
    </Zoomable>
  )
}

function StepRow({ step }: { step: StepProps }) {
  return (
    <motion.div
      {...inViewProps}
      variants={slideInRight}
      className="grid items-start gap-8 lg:grid-cols-[1fr_1.3fr]"
    >
      <div className="flex flex-col gap-4 lg:sticky lg:top-24">
        <span className="inline-flex h-12 w-12 items-center justify-center rounded-xl border border-brand/30 bg-brand/10 text-xl font-semibold text-brand-soft">
          {step.index}
        </span>
        <h3 className="text-xl font-medium leading-snug md:text-2xl">{step.title}</h3>
        <p className="text-base leading-relaxed text-ink-muted md:text-lg">{step.body}</p>
      </div>

      <div className="flex flex-col gap-6">
        {step.images.map((image) => (
          <StepImageBlock key={image.src} image={image} />
        ))}
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
