# Prompt 0001: Define the foundation stage

- Date: 2026-09-26
- Input state: repository initialized with no application code

## Human request

Initialize AquaVol as a clean hackathon workspace before implementation begins.
Establish the project constraints, specification workflow, and implementation
gates. All architecture and application code will be designed and written from
scratch after the product behavior is approved.

Use the following initial technical direction:

- React, TypeScript, and Vite for the frontend
- Node.js and TypeScript for the backend
- Solidity and Foundry for smart contracts
- Base Sepolia for public testnet deployment
- Python for a Black-Scholes reference model

Use Aqua or SwapVM contracts, preserve an incremental Git history, and retain
the specifications and AI-development artifacts required by the event rules.

Do not push anything to GitHub.

## AI interpretation

A complete application scaffold is premature because AquaVol's position and
economic lifecycle have not been selected. Create documentation that fixes
known constraints, exposes unresolved decisions, establishes dependency and
repository controls, and defines the gate for later implementation.

Do not generate React, Node.js, Solidity, Foundry, or Python application code in
this stage.

## Decisions intentionally left open

- The exact DeFi position and participant incentives
- The role of Black-Scholes in quoting or settlement
- Market-data and volatility trust assumptions
- Whether the position needs a custom SwapVM instruction
- The canonical demo assets and token-transfer sequence
