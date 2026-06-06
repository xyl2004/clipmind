import { CapabilitiesSection } from "@/components/CapabilitiesSection"
import { CtaSection } from "@/components/CtaSection"
import { HeroSection } from "@/components/HeroSection"
import { NavBar } from "@/components/NavBar"
import { ScenarioOneSection } from "@/components/ScenarioOneSection"
import { ScenarioTwoSection } from "@/components/ScenarioTwoSection"
import { TechStackSection } from "@/components/TechStackSection"

export default function Home() {
  return (
    <>
      <NavBar />
      <HeroSection />
      <ScenarioOneSection />
      <ScenarioTwoSection />
      <CapabilitiesSection />
      <TechStackSection />
      <CtaSection />
    </>
  )
}
