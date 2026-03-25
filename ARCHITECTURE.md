# Xcrow Protocol — Architecture

## The USDC Payment Layer for the ERC-8004 Agent Economy

**Xcrow** is the missing payment primitive for ERC-8004. While ERC-8004 handles identity, reputation, and validation, it explicitly states that "payments are orthogonal to this protocol." Xcrow fills that gap with USDC escrow, instant platform settlement, reputation-weighted pricing, and cross-chain settlement via CCTP V2.

---

## Protocol Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Xcrow Protocol                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐   ┌──────────────────┐   ┌────────────────┐  │
│  │  Xcrow       │   │  Reputation      │   │  CrossChain    │  │
│  │  Escrow      │──▶│  Pricer          │──▶│  Settler       │  │
│  │              │   │                  │   │  (CCTP V2)     │  │
│  └──────┬───────┘   └────────┬─────────┘   └───────┬────────┘  │
│         │                    │                      │           │
│         ▼                    ▼                      ▼           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Xcrow Router                           │   │
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
- `createJobByWallet()` — Client deposits USDC into escrow, specifying the agent wallet, task description hash, deadline, and ERC-8004 agent ID. Job starts immediately in `InProgress` status.
- `completeAndSettle(jobId)` — **Primary settlement path.** Owner-only atomic function that completes and settles a job in one transaction. The platform server calls this immediately after the agent delivers output. Pays the agent owner instantly.
- `completeJob()` — Agent marks job done (legacy path, used if manual settlement is preferred).
- `settleJob()` — Client manually releases funds (legacy path).
- `cancelJob()` — Client can cancel before delivery; full refund.
- `disputeJob()` — Either party can dispute; resolved by owner arbitration or timeout refund.

**Fee model:**
- Protocol fee: 2.5% on successful completion (configurable, max 10%)
- Fees accumulate in the contract; withdrawable by protocol treasury

**Job lifecycle:**
```
Created (InProgress) --> Settled  (platform calls completeAndSettle — instant)
                     --> Cancelled (client cancels before delivery)
                     --> Disputed --> Refunded (timeout) / Settled (owner resolves)
                     --> Expired  (deadline passed)
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
5. Uses CCTP V2 Hooks for post-transfer automation

**CCTP V2 integration points:**
- `TokenMessengerV2.depositForBurnWithCaller()` — Burns USDC on source chain
- `MessageTransmitterV2.receiveMessage()` — Mints USDC on destination chain
- Hooks — Trigger post-settlement actions on destination chain

### 4. XcrowRouter.sol

Single entry point for all protocol interactions. Abstracts complexity, routes calls to the right sub-contract, and handles cross-chain logic.

**Key functions:**
- `hireAgentByWalletWithPermit()` — Hire agent with EIP-2612 gasless approval + USDC escrow in one tx
- `settleAndPay()` — Client manually releases payment (same-chain or cross-chain)
- `cancelJobViaRouter()` — Client cancels and gets refund
- `disputeJobViaRouter()` — Initiate dispute
- `submitFeedback()` — Client submits star rating after settlement
- `getQuote()` — Get reputation-weighted price for an agent

---

## Settlement Flow

The default integration uses **instant platform settlement**:

```
1. Client calls hireAgentByWalletWithPermit → USDC locked in escrow, job InProgress
2. Platform server dispatches task to agent endpoint
3. Agent returns output
4. Platform server calls completeAndSettle → agent owner paid instantly
5. Client reviews output and optionally submits star rating
```

No manual steps, no waiting periods. The agent gets paid as soon as they deliver.

**Fallback paths** (still available in the contract):
- Client can call `settleAndPay` manually at any time
- `completeJob` + `autoSettle` for trustless settlement with challenge window (legacy)
- `submitProofOfWork` for on-chain output anchoring (legacy)

---

## Chain Deployment Strategy

### Phase 1: Arc Testnet (Current)

| Contract | Arc Testnet |
|----------|-------------|
| XcrowEscrow | `0x165a9040dC9C31be0bDeEd142a63Dd0210998F4D` |
| XcrowRouter | `0xb8b5d656660d2Cde7CDebAEbcb0bD4e5A153B887` |
| ReputationPricer | `0x7bE3BD8996140275c34BD2C3F606Adac9d3CCEA6` |
| CrossChainSettler | `0x421cFe5a9371B45aA300EBCFB88181a11Be826aB` |
| CCTP TokenMessengerV2 | `0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA` |
| CCTP Domain | 26 |

### Phase 2: Mainnet
Deploy to Ethereum (Domain 0) + Base (Domain 6) + Arbitrum (Domain 3) first, then expand.

---

## Integration with ERC-8004

Xcrow reads from ERC-8004 but never writes to it directly (writes go through the Router).

**Identity Registry (read):**
- `ownerOf(agentId)` — Resolve payout address (agent owner receives payment)
- `getAgentWallet(agentId)` — Get agent's operational wallet address
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
    "chainId": "5042002",
    "txHash": "0x..."
  }
}
```
Xcrow auto-populates this after settlement, creating a verifiable link between payment and reputation feedback.

---

## Security Model

1. **No custody risk** — Escrow holds USDC only for active jobs; never pools funds
2. **Instant settlement** — `completeAndSettle` is owner-only and atomic; platform settles immediately after agent delivers
3. **Client protection** — Clients can cancel before delivery or dispute to block payment
4. **Payout to owner** — Payments route to `ownerOf(agentId)` via ERC-8004, not arbitrary addresses
5. **Timelock disputes** — If no resolution in N seconds, client gets refund (configurable `disputeTimeout`)
6. **Cross-chain atomicity** — CCTP V2 ensures 1:1 burn-and-mint; no wrapped tokens or liquidity pools
7. **Reentrancy protection** — All state changes before external calls; ReentrancyGuard on all public functions
8. **Pausable** — Protocol can be paused in emergencies

---

## Tech Stack

- **Solidity** ^0.8.20 (contracts)
- **Foundry** (testing + deployment)
- **OpenZeppelin** (ReentrancyGuard, Pausable, Ownable, IERC20, SafeERC20)
- **CCTP V2 interfaces** (TokenMessengerV2, MessageTransmitterV2)
- **ERC-8004 interfaces** (IIdentityRegistry, IReputationRegistry)
- **Frontend** — Next.js + wagmi + viem (Arcade marketplace)

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
│   └── Deploy.s.sol
├── foundry.toml
├── ARCHITECTURE.md
└── README.md
```
