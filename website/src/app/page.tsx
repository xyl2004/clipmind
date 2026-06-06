import { HeroSection } from "@/components/HeroSection"
import { NavBar } from "@/components/NavBar"
import { ScenarioOneSection } from "@/components/ScenarioOneSection"
import { ScenarioTwoSection } from "@/components/ScenarioTwoSection"

export default function Home() {
  return (
    <>
      <NavBar />
      <HeroSection />
      <ScenarioOneSection />
      <ScenarioTwoSection />
    </>
  )
}
