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
        <motion.p variants={fadeUp} className="text-lg text-ink-muted md:text-xl">
          你的区块链 AI 助手 · 选中即调研，对话即交易。
        </motion.p>
        <motion.div
          variants={fadeUp}
          className="flex flex-wrap items-center justify-center gap-4"
        >
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
