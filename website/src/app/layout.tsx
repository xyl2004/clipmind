import type { Metadata } from "next"
import { Inter, JetBrains_Mono } from "next/font/google"
import { MotionProvider } from "@/components/motion/MotionProvider"
import "./globals.css"

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
})

const mono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jb-mono",
  display: "swap",
})

export const metadata: Metadata = {
  metadataBase: new URL("https://clipmind.vercel.app"),
  title: "ClipMind — 在任何页面，唤起你的区块链 AI 助手",
  description:
    "macOS 悬浮窗钱包助手。选中文字 · ⌃⌥W 唤起 · 项目调研 / 代币交易 / 转账 一气呵成。",
  openGraph: {
    title: "ClipMind",
    description: "在任何页面，唤起你的区块链 AI 助手",
    images: ["/og-image.png"],
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="zh-CN" className={`${inter.variable} ${mono.variable}`}>
      <body className="bg-surface-base text-ink min-h-screen">
        <MotionProvider>{children}</MotionProvider>
      </body>
    </html>
  )
}
