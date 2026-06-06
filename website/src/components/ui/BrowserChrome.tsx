import type { ReactNode } from "react"

interface BrowserChromeProps {
  children: ReactNode
  className?: string
  label?: string
}

export function BrowserChrome({ children, className = "", label }: BrowserChromeProps) {
  return (
    <div
      className={`overflow-hidden rounded-xl border border-surface-border bg-surface-raised shadow-[0_30px_80px_rgba(0,0,0,0.5)] ${className}`}
    >
      <div className="flex items-center gap-1.5 border-b border-surface-border bg-black/30 px-4 py-3">
        <span className="h-3 w-3 rounded-full bg-red-500/70" />
        <span className="h-3 w-3 rounded-full bg-yellow-500/70" />
        <span className="h-3 w-3 rounded-full bg-green-500/70" />
        {label && (
          <span className="ml-auto text-xs text-ink-subtle">{label}</span>
        )}
      </div>
      <div>{children}</div>
    </div>
  )
}
