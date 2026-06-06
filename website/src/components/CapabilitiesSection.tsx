"use client"

import Image from "next/image"
import { motion } from "framer-motion"
import { GlassCard } from "@/components/ui/GlassCard"
import { TagPill } from "@/components/ui/TagPill"
import { fadeUp, inViewProps, staggerContainer } from "@/lib/motion-variants"

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
