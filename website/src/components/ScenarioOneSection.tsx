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
              在任何页面选中项目名 →{" "}
              <kbd className="rounded bg-surface-raised px-1.5 py-0.5 font-mono text-sm">⌃⌥W</kbd>{" "}
              → 立刻拿到结构化调研。
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
