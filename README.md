# Xcrow Protocol

Xcrow is a USDC escrow and payment settlement protocol for the AI agent economy, built on the Arc Network. It provides trustless job creation, execution tracking, and payment release between clients and AI agents, with native integration into Arc's ERC-8004 identity and reputation standard.

---

## Overview

When a client hires an AI agent, Xcrow locks the agreed USDC amount in escrow at the moment of hire. Funds remain locked until the agent completes the job and the client releases payment. If either party acts in bad faith, the protocol enforces cancellation, dispute resolution, or expiry refunds without requiring a trusted intermediary.

Xcrow also writes proof-of-payment feedback directly to the ERC-8004 Reputation Registry on every settled job, building a tamper-proof on-chain track record for each agent over time.

---

## Architecture

The protocol is composed of four core contracts and a shared type library.

### XcrowEscrow

The escrow vault. Holds USDC for the duration of a job and enforces the job lifecycle state machine. Supports both ERC-8004 identity-based hiring and direct wallet-based hiring.

Job lifecycle:

```
Created -> Accepted -> InProgress -> Completed -> Settled
                                               -> Disputed -> Resolved
         -> Cancelled (pre-acceptance)
         -> Expired   (deadline passed)
         -> Refunded  (dispute resolved in client's favor)
```

Key mappings:
- `clientJobs` — all jobs created by a client address
- `agentJobs` — all jobs assigned to an ERC-8004 agent ID
- `agentWalletJobs` — all jobs assigned to an agent wallet address (wallet-based hiring)

### XcrowRouter

The single entry point for all client-facing interactions. Orchestrates the escrow, reputation pricer, and cross-chain settler. Stores the `originalClient` mapping to correctly attribute refunds and feedback for jobs routed through it.

Hiring modes supported:
- `hireAgent` — hire by ERC-8004 agent ID
- `hireAgentWithPermit` — same as above with EIP-2612 permit (single transaction, no pre-approval)
- `hireAgentByWalletWithPermit` — hire by agent wallet address directly, no ERC-8004 lookup required
- `hireAgentWithQuote` — hire at a reputation-weighted price from the pricer
- `hireAgentCrossChain` — hire with CCTP V2 cross-chain payout

Post-settlement:
- `settleAndPay` — releases USDC to the agent and auto-submits proof-of-payment to the ERC-8004 Reputation Registry
- `submitFeedback` — allows the client to submit a star rating and optional review URI after settlement
- `rejectJobViaRouter` — agent rejects an assigned job; USDC is refunded directly to the original client
- `cancelJobViaRouter` — client cancels a job before it is accepted; USDC is refunded in full
- `disputeJobViaRouter` — either party raises a dispute for owner arbitration

### ReputationPricer

Computes reputation-weighted price quotes for agents registered on ERC-8004. Reads aggregated feedback from the Reputation Registry using a configurable set of trusted reviewers to filter out Sybil-manipulated scores.

Pricing model:
- Agents with no reviews, or fewer than `minReviewCount`, receive a base 1x multiplier
- Agents with positive reputation receive a premium up to `maxPremiumBps` above base rate
- Agents with negative reputation receive a penalty, floored at 0.1x to prevent zero-cost exploitation

### CrossChainSettler

Handles cross-chain USDC payouts via Circle's CCTP V2. When a job is settled cross-chain, the escrow releases funds to this contract, which burns USDC on Arc and instructs Circle to mint the equivalent on the destination chain directly to the agent's wallet.

Supported destination domains: Ethereum, Arbitrum, Base.

---

## ERC-8004 Integration

Xcrow is built around Arc's ERC-8004 standard for AI agent identity and reputation.

- **Identity Registry** (`0x8004A818BFB912233c491871b3d84c89A494BD9e`) — used to resolve agent wallet addresses from ERC-8004 token IDs and verify agent ownership
- **Reputation Registry** (`0x8004B663056A597Dffe9eCcC1965A193B7388713`) — receives proof-of-payment feedback on every settled job via `giveFeedback`, and star ratings submitted by clients via `submitFeedback`

Every job settled through the router contributes to the agent's on-chain reputation, which in turn affects their pricing multiplier through the ReputationPricer.

---

## Deployed Contracts — Arc Testnet

| Contract | Address |
|---|---|
| XcrowEscrow | `0x9D157b6fa143a5778c017FB233ee972387Ac1aE3` |
| XcrowRouter | `0x81c3F812454B25D9696a66541788996532f89278` |
| ReputationPricer | `0x9FD2686839350350272cA7717BFaE6409C0563c1` |
| CrossChainSettler | `0xA3f6CB47D43Fc92c33b75DaE6cd5FfaC5950cEB0` |
| ERC-8004 Identity | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| ERC-8004 Reputation | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |
| USDC | `0x3600000000000000000000000000000000000000` |

Chain ID: `5042002`

---

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Setup

```shell
git clone https://github.com/your-org/xcrow
cd xcrow
forge install
```

Create a `.env` file:

```
PRIVATE_KEY=your_deployer_private_key
ARC_RPC_URL=https://rpc.testnet.arc.network
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Deploy

```shell
forge script script/Deploy.s.sol --rpc-url https://rpc.testnet.arc.network --broadcast
```

---

## Protocol Fees

The protocol charges a configurable fee in basis points on each job, deducted from the escrowed amount at settlement. Fees accumulate in the escrow contract and are withdrawable by the contract owner to a designated treasury address. The default fee is 2.5% (250 bps). The maximum is capped at 10% (1000 bps).

---

## Security

- All state-changing functions use `ReentrancyGuard`
- The escrow and router are `Pausable` for emergency stops
- Agent acceptance and job completion are gated to the assigned `agentWallet`
- Refunds on rejection and cancellation are routed through `originalClient` to prevent USDC from being stranded in the router
- `CrossChainSettler` restricts `settleCrossChain` to authorized callers only
- Dispute resolution is owner-arbitrated with a configurable timeout for auto-refund

---

## License

GPL-3.0
