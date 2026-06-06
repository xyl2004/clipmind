"use client"

import { motion, useMotionValue, useTransform } from "framer-motion"
import { useEffect, useState } from "react"
import { BrowserChrome } from "@/components/ui/BrowserChrome"
import { GradientText } from "@/components/ui/GradientText"
import { TagPill } from "@/components/ui/TagPill"
import { Zoomable } from "@/components/ui/Zoomable"
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
            选中文字 ·{" "}
            <kbd className="rounded bg-surface-raised px-1.5 py-0.5 font-mono text-sm">⌃⌥W</kbd>{" "}
            唤起 · 调研、问答、交易一气呵成。
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
            visible: {
              opacity: 1,
              scale: 1,
              transition: { duration: 0.7, ease: [0.16, 1, 0.3, 1] },
            },
          }}
          style={{ rotateX, rotateY, transformPerspective: 1200 }}
          className="relative"
        >
          <Zoomable
            label="放大查看演示视频"
            expandedContent={
              <video
                src="/hero-demo.mp4"
                poster="/hero-demo-poster.jpg"
                autoPlay
                loop
                playsInline
                controls
                className="block max-h-[90vh] max-w-[90vw] rounded-lg"
              />
            }
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
          </Zoomable>
        </motion.div>
      </div>
    </section>
  )
}
