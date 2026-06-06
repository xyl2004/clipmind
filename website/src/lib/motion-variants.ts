import type { Variants } from "framer-motion"

const easing = [0.16, 1, 0.3, 1] as const

export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 32 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.6, ease: easing } },
}

export const slideInLeft: Variants = {
  hidden: { opacity: 0, x: -40 },
  visible: { opacity: 1, x: 0, transition: { duration: 0.7, ease: easing } },
}

export const slideInRight: Variants = {
  hidden: { opacity: 0, x: 40 },
  visible: { opacity: 1, x: 0, transition: { duration: 0.7, ease: easing } },
}

export const scaleIn: Variants = {
  hidden: { opacity: 0, scale: 0.96 },
  visible: { opacity: 1, scale: 1, transition: { duration: 0.5, ease: "easeOut" } },
}

export function staggerContainer(delay = 0.08): Variants {
  return {
    hidden: {},
    visible: { transition: { staggerChildren: delay } },
  }
}

export const inViewProps = {
  initial: "hidden" as const,
  whileInView: "visible" as const,
  viewport: { once: true, amount: 0.3 } as const,
}
