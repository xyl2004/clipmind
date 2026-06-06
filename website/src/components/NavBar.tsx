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
              <Link href={anchor.href} className="transition-colors hover:text-ink">
                {anchor.label}
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </nav>
  )
}
