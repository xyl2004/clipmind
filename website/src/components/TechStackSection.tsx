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
  accentColor: string
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
    accentColor: "rgba(16, 185, 129, 0.35)",
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
    accentColor: "rgba(139, 92, 246, 0.35)",
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
    accentColor: "rgba(6, 182, 212, 0.35)",
  },
]

function TechRow({ block }: { block: TechBlock }) {
  return (
    <motion.div {...inViewProps} variants={slideInRight}>
      <GlassCard className="relative overflow-hidden p-8">
        <div
          className="pointer-events-none absolute -left-20 top-1/2 h-72 w-72 -translate-y-1/2 rounded-full blur-3xl"
          style={{
            background: `radial-gradient(circle, ${block.accentColor}, transparent 70%)`,
          }}
        />
        <div className="relative grid items-start gap-6 lg:grid-cols-[120px_1fr]">
          <span className="font-mono text-3xl font-semibold text-ink-subtle">
            {block.badge}
          </span>
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
