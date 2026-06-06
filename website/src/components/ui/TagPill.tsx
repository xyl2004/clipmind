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
