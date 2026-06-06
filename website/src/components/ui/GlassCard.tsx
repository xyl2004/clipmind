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
