import { Brand } from "./components/Brand";
import { Hero } from "./components/Hero";
import { StrategyBuilder } from "./components/StrategyBuilder";
import { DeploymentContracts, ProtocolProof } from "./components/ProtocolProof";
import { LiveMarketStatus } from "./components/LiveMarketStatus";
import { WalletPanel } from "./components/WalletPanel";
import { deployment } from "./data/deployment";

function App() {
  return (
    <div className="app">
      <div className="backdrop" aria-hidden="true"><span /><span /><span /></div>
      <header className="topbar">
        <div className="topbar-inner">
          <Brand />
          <nav aria-label="Primary">
            <a href="#markets">Markets</a>
            <a href="#strategy">Strategy</a>
            <a href="#trade">Trade</a>
            <a href="#how">How it works</a>
          </nav>
          <span className="network-chip"><i className="pulse" />{deployment.network}</span>
        </div>
      </header>
      <main>
        <Hero />
        <LiveMarketStatus />
        <StrategyBuilder />
        <WalletPanel />
        <ProtocolProof />
        <DeploymentContracts />
      </main>
      <footer className="footer">
        <div className="footer-inner">
          <div className="footer-brand">
            <Brand size={28} />
            <p>Programmable, fully collateralized options on Base.</p>
          </div>
          <div className="footer-meta">
            <span>Base Sepolia test assets only · Not production software</span>
            <span>Powered by Aqua + SwapVM</span>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default App;
