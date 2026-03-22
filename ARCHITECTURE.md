# Xcrow Protocol — Architecture

## The USDC Payment Layer for the ERC-8004 Agent Economy

**Xcrow** is the missing payment primitive for ERC-8004. While ERC-8004 handles identity, reputation, and validation, it explicitly states that "payments are orthogonal to this protocol." Xcrow fills that gap with USDC escrow, reputation-weighted pricing, and cross-chain settlement via CCTP V2.

---

## Protocol Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Xcrow Protocol                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐   ┌──────────────────┐   ┌────────────────┐  │
│  │  Xcrow    │   │  Reputation      │   │  CrossChain    │  │
│  │  Escrow      │──▶│  Pricer          │──▶│  Settler       │  │
│  │              │   │                  │   │  (CCTP V2)     │  │
│  └──────┬───────┘   └────────┬─────────┘   └───────┬────────┘  │
│         │                    │                      │           │
│         ▼                    ▼                      ▼           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Xcrow Router                        │   │
│  │         (Entry point + orchestration layer)              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  External Dependencies                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ ERC-8004    │  │ USDC         │  │ CCTP V2                │ │
│  │ Identity +  │  │ (ERC-20)     │  │ TokenMessengerV2 +     │ │
│  │ Reputation  │  │              │  │ MessageTransmitterV2   │ │
│  └─────────────┘  └──────────────┘  └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Core Contracts

### 1. XcrowEscrow.sol

The payment engine. Handles USDC deposits, holds funds during task execution, and releases on completion or refunds on dispute.

**Key flows:**
- `createJob()` — Client deposits USDC into escrow, specifying the agent (by ERC-8004 agentId), task description hash, deadline, and agreed price.
- `completeJob()` — Agent marks job done, transitioning status to Completed.
- `submitProofOfWork(jobId, proofHash)` — Agent anchors `keccak256(outputContent)` on-chain. Sets `proofSubmittedAt` and starts the `settlementWindow` (default 48h).
- `autoSettle(jobId)` — Callable by anyone once `block.timestamp >= proofSubmittedAt + settlementWindow` and no dispute is active. Releases payment to agent trustlessly.
- `settleJob()` — Client manually confirms and releases funds at any time after Completed status.
- `disputeJob()` — Either party can dispute before auto-settlement occurs; resolved by owner arbitration or timeout refund.
- `cancelJob()` — Client can cancel before agent accepts; full refund.

**Fee model:**
- Protocol fee: 2.5% on successful completion (configurable by governance)
- Fees accumulate in the contract; withdrawable by protocol treasury

**Job lifecycle:**
```
Created → Accepted → InProgress → Completed → [PoW submitted] → [48h window] → Settled (auto)
   │          │           │            │                                      ↗
   │          │           │            └──────────────────────────────────────  Settled (manual)
   │          │           │            └→ Disputed → Refunded (timeout) / Settled (owner)
   ▼          ▼           ▼
Cancelled  Expired    Disputed
```

### 2. ReputationPricer.sol

Dynamic pricing oracle that reads ERC-8004 reputation scores and computes suggested rates.

**Pricing formula:**
```
effectiveRate = baseRate × reputationMultiplier(agentId)

reputationMultiplier = 1 + (reputationScore / MAX_SCORE) × MAX_PREMIUM

Example:
  baseRate = 10 USDC
  reputationScore = 85/100
  MAX_PREMIUM = 2x
  effectiveRate = 10 × (1 + 0.85 × 2) = 27 USDC
```

**Features:**
- Reads from ERC-8004 Reputation Registry's `getSummary()` function
- Configurable trusted reviewers list (to filter Sybil-resistant feedback)
- Agents can set their own base rate; multiplier applies on top
- Price suggestions are advisory — final price is agreed between client and agent

### 3. CrossChainSettler.sol

CCTP V2 integration for cross-chain USDC settlement. When client and agent are on different chains, this contract handles the burn-and-mint flow.

**How it works:**
1. Client on Chain A calls `createCrossChainJob()` with USDC
2. USDC is held in escrow on Chain A
3. On completion, CrossChainSettler burns USDC via CCTP V2's `depositForBurnWithCaller()`
4. Agent receives minted USDC on Chain B
5. Uses CCTP V2 Hooks for post-transfer automation (e.g., auto-feedback submission)

**CCTP V2 integration points:**
- `TokenMessengerV2.depositForBurnWithCaller()` — Burns USDC on source chain
- `MessageTransmitterV2.receiveMessage()` — Mints USDC on destination chain
- Hooks — Trigger post-settlement actions on destination chain

### 4. XcrowRouter.sol

Single entry point for all protocol interactions. Abstracts complexity, routes calls to the right sub-contract, and handles cross-chain logic.

**Key functions:**
- `hireAgent()` — Discover agent via ERC-8004, check reputation, get price quote, create escrow
- `hireAgentCrossChain()` — Same flow but routes through CrossChainSettler
- `settleAndPay()` — Client manually releases payment (same-chain or cross-chain)
- `autoSettleViaRouter()` — Trustless release after PoW window elapses; also submits ERC-8004 reputation feedback
- `getQuote()` — Get reputation-weighted price for an agent

---

## Chain Deployment Strategy

### Phase 1: Testnet (Sepolia + Base Sepolia)
Both ERC-8004 and CCTP V2 are deployed on these testnets. Start here.

| Contract | Ethereum Sepolia | Base Sepolia |
|----------|-----------------|--------------|
| CCTP TokenMessengerV2 | `0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA` | `0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA` |
| CCTP MessageTransmitterV2 | `0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275` | `0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275` |
| USDC (Sepolia) | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| CCTP Domain | 0 | 6 |

### Phase 2: Arc Testnet
Arc is already on CCTP V2 testnet (Domain 26). Direct bridge to your Arcade ecosystem.

| Contract | Arc Testnet |
|----------|-------------|
| CCTP TokenMessengerV2 | `0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA` |
| CCTP MessageTransmitterV2 | `0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275` |
| CCTP Domain | 26 |

### Phase 3: Mainnet
Deploy to Ethereum (Domain 0) + Base (Domain 6) + Arbitrum (Domain 3) first, then expand.

---

## Integration with ERC-8004

Xcrow reads from ERC-8004 but never writes to it. The integration points:

**Identity Registry (read):**
- `ownerOf(agentId)` — Verify agent ownership
- `getAgentWallet(agentId)` — Get agent's payment address
- `tokenURI(agentId)` → Registration file — Get agent capabilities/endpoints

**Reputation Registry (read + write):**
- `getSummary(agentId, clientAddresses, tag1, tag2)` — Fetch reputation for pricing
- `giveFeedback(agentId, value, ...)` — Auto-submit feedback with proof of payment after settlement

**Proof of Payment in Feedback:**
ERC-8004's feedback file supports a `proofOfPayment` field:
```json
{
  "proofOfPayment": {
    "fromAddress": "0x...",
    "toAddress": "0x...",
    "chainId": "11155111",
    "txHash": "0x..."
  }
}
```
Xcrow auto-populates this after settlement, creating a verifiable link between payment and reputation feedback.

---

## Security Model

1. **No custody risk** — Escrow holds USDC only for active jobs; never pools funds
2. **Trustless agent protection** — `submitProofOfWork` + `autoSettle` ensures agents cannot be ghosted by clients after delivering work; payment releases automatically after the challenge window
3. **Client dispute window** — 48h configurable window gives clients time to dispute bad output before auto-settlement triggers
4. **Timelock disputes** — If no resolution in N seconds, client gets refund (configurable `disputeTimeout`)
5. **Agent wallet verification** — Payments go to ERC-8004's verified `agentWallet`, not arbitrary addresses
6. **Cross-chain atomicity** — CCTP V2 ensures 1:1 burn-and-mint; no wrapped tokens or liquidity pools
7. **Reentrancy protection** — All state changes before external calls; ReentrancyGuard on all public functions
8. **Pausable** — Protocol can be paused in emergencies

---

## Tech Stack

- **Solidity** ^0.8.20 (contracts)
- **Foundry** (testing + deployment)
- **OpenZeppelin** (ReentrancyGuard, Pausable, Ownable, IERC20)
- **CCTP V2 interfaces** (TokenMessengerV2, MessageTransmitterV2)
- **ERC-8004 interfaces** (IIdentityRegistry, IReputationRegistry)
- **Subgraph** (The Graph — index jobs, settlements, cross-chain events)
- **Frontend** — Next.js + wagmi + viem (later phase)

---

## File Structure

```
xcrow-protocol/
├── src/
│   ├── interfaces/
│   │   ├── IXcrowEscrow.sol
│   │   ├── IERC8004Identity.sol
│   │   ├── IERC8004Reputation.sol
│   │   └── ICCTPv2.sol
│   ├── core/
│   │   ├── XcrowEscrow.sol
│   │   ├── ReputationPricer.sol
│   │   ├── CrossChainSettler.sol
│   │   └── XcrowRouter.sol
│   └── libraries/
│       └── XcrowTypes.sol
├── test/
│   ├── XcrowEscrow.t.sol
│   ├── ReputationPricer.t.sol
│   ├── CrossChainSettler.t.sol
│   └── XcrowRouter.t.sol
├── script/
│   ├── Deploy.s.sol
│   └── DeployCrossChain.s.sol
├── foundry.toml
└── README.md
```
