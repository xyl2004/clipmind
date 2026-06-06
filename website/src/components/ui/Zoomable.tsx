"use client"

import {
  cloneElement,
  isValidElement,
  useEffect,
  useState,
  type ReactElement,
  type ReactNode,
} from "react"
import { createPortal } from "react-dom"
import { AnimatePresence, motion } from "framer-motion"

interface ZoomableProps {
  children: ReactNode
  expandedContent?: ReactNode
  label?: string
}

export function Zoomable({ children, expandedContent, label }: ZoomableProps) {
  const [open, setOpen] = useState(false)
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false)
    }
    window.addEventListener("keydown", onKey)
    const original = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      window.removeEventListener("keydown", onKey)
      document.body.style.overflow = original
    }
  }, [open])

  let expanded: ReactNode = expandedContent ?? children
  if (!expandedContent && isValidElement(children)) {
    // For raw <video> children, force controls + larger size in lightbox
    const tag = (children as ReactElement<{ controls?: boolean; className?: string }>).type
    if (typeof tag === "string" && tag === "video") {
      expanded = cloneElement(
        children as ReactElement<{ controls?: boolean; className?: string }>,
        {
          controls: true,
          className: "block max-h-[90vh] max-w-[90vw] rounded-lg",
        }
      )
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={label ?? "放大查看"}
        className="block w-full cursor-zoom-in rounded-xl text-left outline-none transition-opacity hover:opacity-95 focus-visible:ring-2 focus-visible:ring-brand"
      >
        {children}
      </button>

      {mounted &&
        createPortal(
          <AnimatePresence>
            {open && (
              <motion.div
                key="lightbox"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="fixed inset-0 z-[100] flex cursor-zoom-out items-center justify-center bg-black/85 p-4 backdrop-blur-sm md:p-10"
                onClick={() => setOpen(false)}
              >
                <button
                  type="button"
                  aria-label="关闭"
                  onClick={() => setOpen(false)}
                  className="absolute right-4 top-4 z-10 rounded-full bg-white/10 p-2 text-white backdrop-blur transition-colors hover:bg-white/20"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <line x1="18" y1="6" x2="6" y2="18" />
                    <line x1="6" y1="6" x2="18" y2="18" />
                  </svg>
                </button>

                <motion.div
                  initial={{ scale: 0.95, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  exit={{ scale: 0.95, opacity: 0 }}
                  transition={{ duration: 0.2, ease: [0.16, 1, 0.3, 1] }}
                  className="relative flex max-h-full max-w-full items-center justify-center cursor-default"
                  onClick={(event) => event.stopPropagation()}
                >
                  {expanded}
                </motion.div>
              </motion.div>
            )}
          </AnimatePresence>,
          document.body
        )}
    </>
  )
}
