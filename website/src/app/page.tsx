import { Nav, Scrubber, Footer } from "@/components/Chrome";
import {
  Hero, ProofBand, Statement, ProductShot, Features,
  Notch, Native, Privacy, MoreToCome, Install, Support,
} from "@/components/Sections";

export default function Page() {
  return (
    <>
      <div className="aurora" aria-hidden>
        <div className="glow-wrap wrap-a"><div className="glow glow-a" /></div>
        <div className="glow-wrap wrap-b"><div className="glow glow-b" /></div>
        <div className="glow-wrap wrap-c"><div className="glow glow-c" /></div>
      </div>

      <Nav />
      <Scrubber />

      <main>
        <Hero />
        <ProofBand />
        <Statement />
        <ProductShot />
        <Features />
        <hr className="fault rail" />
        <Notch />
        <Native />
        <Privacy />
        <MoreToCome />
        <Install />
        <Support />
      </main>

      <Footer />
    </>
  );
}
