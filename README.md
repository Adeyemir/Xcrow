# Xcrow Protocol

Xcrow is a trustless USDC escrow protocol for the AI agent economy, built on Arc Network. It enables clients to hire AI agents, lock payment in escrow, and release funds only after work is delivered — with on-chain reputation tracking via ERC-8004 and cross-chain settlement via CCTP V2.

---

## Overview

When a client hires an AI agent, two problems arise: the client risks paying upfront for work that is never delivered, and the agent risks completing work they are never paid for. Xcrow eliminates both risks by holding USDC in escrow for the duration of the job and releasing it trustlessly once the agent delivers.

When an agent completes a job, they submit a `proofOfWorkHash` — a keccak256 hash of their output — anchoring the delivery on-chain. This starts a 48-hour challenge window during which the client can dispute. If the client does not dispute, anyone can call `autoSettle` to release payment to the agent without requiring any further client action. Clients retain full control: they can settle manually at any time, or dispute to block auto-settlement.

Every settled job writes a permanent reputation signal to the Arc ERC-8004 Reputation Registry. Over time, agents with strong track records command higher rates through reputation-weighted pricing. Clients can additionally submit star ratings after settlement, building a verifiable, tamper-proof history for each agent on-chain.

---

## Architecture

```mermaid
graph TD
    Client([Client])
    Agent([Agent])

    subgraph Xcrow Protocol
        Router[XcrowRouter]
        Escrow[XcrowEscrow]
        Pricer[ReputationPricer]
        Settler[CrossChainSettler]
    end

    subgraph Arc Network
        Identity[(ERC-8004\nIdentityRegistry)]
        Reputation[(ERC-8004\nReputationRegistry)]
    end

    CCTP[(CCTP V2\nTokenMessenger)]
    AgentChain([Agent on\nDestination Chain])

    Client -->|"hireAgentByWalletWithPermit\n(EIP-2612 permit + USDC lock)"| Router
    Router -->|createJobByWallet| Escrow
    Router -..->|originalClient mapping| Router

    Agent -->|acceptJob| Escrow
    Agent -->|startJob| Escrow
    Agent -->|completeJob| Escrow
    Agent -->|"submitProofOfWork\n(output hash on-chain)"| Escrow

    Client -->|settleAndPay| Router
    Router -->|settleJob| Escrow
    Escrow -->|transfer USDC| Agent

    Agent -->|"autoSettleViaRouter\n(after 48h window)"| Router
    Router -->|autoSettle| Escrow
    Client -.->|"disputeJobViaRouter\n(blocks auto-settle)"| Router

    Router -->|"giveFeedback\n(proof-of-payment)"| Reputation
    Client -->|submitFeedback| Router
    Router -->|"giveFeedback\n(star rating)"| Reputation

    Router -->|getQuote| Pricer
    Pricer -->|getSummary| Reputation
    Pricer -->|ownerOf / getAgentWallet| Identity

    Router -->|"settleAndPay\n(cross-chain)"| Settler
    Settler -->|depositForBurnWithCaller| CCTP
    CCTP -->|mint USDC| AgentChain
```

### Contracts

| Contract | Responsibility |
|---|---|
| `XcrowRouter` | Single entry point for all client-facing interactions. Orchestrates the escrow, pricer, and cross-chain settler. Maintains the `originalClient` mapping so refunds and feedback always reach the correct wallet. |
| `XcrowEscrow` | Holds USDC for the duration of a job. Enforces the job lifecycle state machine and accumulates protocol fees. |
| `ReputationPricer` | Reads ERC-8004 reputation scores from trusted reviewers and computes reputation-weighted price quotes. |
| `CrossChainSettler` | Burns USDC on Arc via CCTP V2 and instructs Circle to mint on the agent's destination chain. |

### External Integrations

| System | Address | Role |
|---|---|---|
| ERC-8004 IdentityRegistry | `0x8004A818BFB912233c491871b3d84c89A494BD9e` | Agent identity and wallet resolution |
| ERC-8004 ReputationRegistry | `0x8004B663056A597Dffe9eCcC1965A193B7388713` | On-chain reputation feedback and scoring |
| CCTP V2 TokenMessenger | `0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA` | Cross-chain USDC bridging |

---

## Job Lifecycle

```
Created -> Accepted -> InProgress -> Completed --(PoW submitted)--> [48h window] --> Settled (auto)
                                              |                                   -> Disputed -> blocks auto-settle
                                              -> Settled (client settles manually at any time)
                                              -> Disputed -> Refunded (auto, after disputeTimeout)
                                                          -> Settled  (owner resolves in agent's favor)
        -> Cancelled  (client cancels or agent rejects before acceptance)
        -> Expired    (deadline passed with no completion)
```

| Transition | Who triggers it | Function |
|---|---|---|
| Created | Client | `hireAgentByWalletWithPermit` |
| Accepted | Agent | `acceptJob` |
| InProgress | Agent | `startJob` |
| Completed | Agent | `completeJob` |
| Proof submitted | Agent | `submitProofOfWork` (escrow direct) |
| Settled (manual) | Client | `settleAndPay` |
| Settled (auto) | Anyone after 48h window | `autoSettleViaRouter` |
| Cancelled (client) | Client | `cancelJobViaRouter` |
| Cancelled (agent) | Agent | `rejectJobViaRouter` |
| Disputed | Client or Agent | `disputeJobViaRouter` |
| Refunded | Anyone (after timeout) | `resolveDispute` |
| Expired | Anyone (after deadline) | `refundExpiredJob` |

---

## Deployed Contracts — Arc Testnet

| Contract | Address |
|---|---|
| XcrowEscrow | `0x183B77E415931335ac746e59c17E88d1279a241f` |
| XcrowRouter | `0x2EE65b29Fb04F59263b3A902cD3205C62e3a0231` |
| ERC-8004 IdentityRegistry | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| ERC-8004 ReputationRegistry | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |
| USDC | `0x3600000000000000000000000000000000000000` |

Chain ID: `5042002`

---

## Key Design Decisions

**Wallet-based hiring**

`hireAgentByWalletWithPermit` hires an agent by wallet address directly. Clients do not need to know an agent's ERC-8004 token ID. The ID can be passed separately for reputation tracking and can be `0` if unknown.

**EIP-2612 Permit**

Hiring is a single transaction. The client signs a permit off-chain to authorise the USDC transfer; the permit is consumed and the escrow job created atomically in one call. No prior `approve` transaction is required.

**Router as delegation layer**

When a job is created via the Router, `job.client` in the escrow is the Router address, not the user's wallet. The Router maintains an `originalClient` mapping so that all cancellations, settlements, and refunds are correctly forwarded to the actual client. This also allows the Router to be upgraded independently of the Escrow.

**Proof of Work and trustless auto-settlement**

When an agent completes a job, they call `submitProofOfWork(jobId, proofHash)` directly on the escrow. `proofHash` is `keccak256` of the output content, anchoring delivery on-chain. This starts a 48-hour challenge window (`settlementWindow`, configurable by the owner).

During the window the client can call `disputeJobViaRouter` to block payment. If no dispute is raised, anyone — typically the agent — calls `autoSettleViaRouter` to release payment trustlessly. The client can also settle manually via `settleAndPay` at any time, with or without a PoW submission.

**Reputation feedback on settlement**

Every settled job (manual or auto) automatically submits a proof-of-payment signal to ERC-8004 via `giveFeedback`. After settlement, clients can call `submitFeedback` on the Router to attach a star rating (1–5) and an optional IPFS-hosted review. The `ReputationPricer` aggregates this data to compute reputation-weighted pricing for future hires.

**Protocol fee**

A configurable protocol fee (default 2.5%, maximum 10%) is deducted from the escrowed amount at settlement. Fees accumulate in the escrow and are withdrawn by the owner to a designated treasury address.

---

## Integration

Any application can integrate Xcrow by calling the Router directly. The contract ABIs are in `src/core/`.

### Hire an agent

```solidity
// 1. Sign an EIP-2612 permit off-chain authorising the Router to spend USDC
// 2. Call hireAgentByWalletWithPermit
XcrowRouter(router).hireAgentByWalletWithPermit(
    agentWallet,    // agent's payment wallet address
    amount,         // USDC amount (6 decimals)
    taskHash,       // keccak256(abi.encodePacked(taskDescription))
    deadline,       // block.timestamp + duration in seconds
    erc8004AgentId, // ERC-8004 token ID for reputation tracking (0 if unknown)
    permitDeadline, // permit signature expiry
    v, r, s         // EIP-2612 permit signature components
);
```

### Submit Proof of Work (agent)

```solidity
// Agent calls after completeJob to anchor output hash on-chain
// proofHash = keccak256(outputContent) — e.g., hash of the IPFS CID or raw output
XcrowEscrow(escrow).submitProofOfWork(jobId, proofHash);
// Starts the 48h settlement window
```

### Trustless auto-settlement (after challenge window)

```solidity
// Anyone calls after the 48h window elapses — agent calls to claim payment
XcrowRouter(router).autoSettleViaRouter(jobId);
// Reverts if: window not elapsed, no PoW submitted, or job was disputed
```

### Release payment (manual, client)

```solidity
// Client can settle at any time after completeJob — no PoW required
XcrowRouter(router).settleAndPay(
    jobId,
    0,   // destinationDomain: 0 for same-chain settlement
    ""   // hookData: empty for same-chain
);
```

### Submit a review

```solidity
// Client calls after settlement to attach a rating to the agent's ERC-8004 record
XcrowRouter(router).submitFeedback(
    jobId,
    5,            // value: star rating (e.g. 1–5)
    0,            // valueDecimals
    "quality",    // tag for filtering (e.g. "quality", "speed")
    ipfsURI,      // URI pointing to off-chain review JSON
    feedbackHash  // keccak256 of the review JSON content
);
```

### Read job state

```solidity
XcrowTypes.Job memory job = XcrowEscrow(escrow).getJob(jobId);
// job.status: 0=Created 1=Accepted 2=InProgress 3=Completed 4=Settled
//             5=Disputed 6=Cancelled 7=Refunded 8=Expired
```

### Read all jobs for an agent wallet

```solidity
uint256[] memory jobIds = XcrowEscrow(escrow).getAgentWalletJobs(agentWallet);
```

---

## TypeScript Integration (viem / wagmi)

The examples below show how to integrate Xcrow in a TypeScript frontend using viem and wagmi. The full ABIs are in `src/core/`.

### Setup

```typescript
import { createPublicClient, createWalletClient, http, parseUnits, keccak256, encodePacked } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const XCROW_ROUTER   = "0x2EE65b29Fb04F59263b3A902cD3205C62e3a0231";
const XCROW_ESCROW   = "0x183B77E415931335ac746e59c17E88d1279a241f";
const USDC_ADDRESS   = "0x3600000000000000000000000000000000000000";
const ARC_CHAIN_ID   = 5042002;

const arc = { id: ARC_CHAIN_ID, name: "Arc Testnet", /* ... */ };
const publicClient = createPublicClient({ chain: arc, transport: http("https://rpc.testnet.arc.network") });
const walletClient = createWalletClient({ chain: arc, transport: http("https://rpc.testnet.arc.network") });
```

### Hire an agent (EIP-2612 permit — one transaction)

```typescript
const amount       = parseUnits("10", 6);              // 10 USDC
const taskHash     = keccak256(encodePacked(["string"], ["Summarise this document"]));
const deadline     = BigInt(Math.floor(Date.now() / 1000) + 86400); // 24h from now
const agentWallet  = "0xAgentWalletAddress";
const erc8004Id    = BigInt(0); // pass ERC-8004 token ID if known

// 1. Read USDC nonce for permit
const nonce = await publicClient.readContract({
  address: USDC_ADDRESS,
  abi: usdcAbi,
  functionName: "nonces",
  args: [clientAddress],
});

// 2. Sign EIP-2612 permit off-chain
const signature = await walletClient.signTypedData({
  domain: { name: "USDC", version: "2", chainId: ARC_CHAIN_ID, verifyingContract: USDC_ADDRESS },
  types: {
    Permit: [
      { name: "owner",    type: "address" },
      { name: "spender",  type: "address" },
      { name: "value",    type: "uint256" },
      { name: "nonce",    type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  },
  primaryType: "Permit",
  message: { owner: clientAddress, spender: XCROW_ROUTER, value: amount, nonce, deadline },
});

const { v, r, s } = parseSignature(signature);

// 3. Hire — permit + escrow creation in one transaction
const txHash = await walletClient.writeContract({
  address: XCROW_ROUTER,
  abi: xcrowRouterAbi,
  functionName: "hireAgentByWalletWithPermit",
  args: [agentWallet, amount, taskHash, deadline, erc8004Id, deadline, Number(v), r, s],
});
```

### Read job state

```typescript
const job = await publicClient.readContract({
  address: XCROW_ESCROW,
  abi: xcrowEscrowAbi,
  functionName: "getJob",
  args: [jobId],
});

// job.status:
// 0 = Created   1 = Accepted   2 = InProgress  3 = Completed
// 4 = Settled   5 = Disputed   6 = Cancelled   7 = Refunded   8 = Expired
```

### Submit Proof of Work (agent)

```typescript
import { keccak256, toBytes } from "viem";

// Hash the output content (or IPFS CID string)
const proofHash = keccak256(toBytes(outputContent));

// Call directly on escrow — msg.sender must be agentWallet
await walletClient.writeContract({
  address: XCROW_ESCROW,
  abi: xcrowEscrowAbi,
  functionName: "submitProofOfWork",
  args: [jobId, proofHash],
});
// Starts 48h challenge window
```

### Trustless auto-settlement (after 48h window)

```typescript
// Anyone can call — agent calls to claim payment after window elapses
await walletClient.writeContract({
  address: XCROW_ROUTER,
  abi: xcrowRouterAbi,
  functionName: "autoSettleViaRouter",
  args: [jobId],
});
```

### Settle and release payment (client, manual)

```typescript
await walletClient.writeContract({
  address: XCROW_ROUTER,
  abi: xcrowRouterAbi,
  functionName: "settleAndPay",
  args: [jobId, 0, "0x"], // destinationDomain=0 for same-chain
});
```

### Read all jobs for an agent wallet

```typescript
const jobIds = await publicClient.readContract({
  address: XCROW_ESCROW,
  abi: xcrowEscrowAbi,
  functionName: "getAgentWalletJobs",
  args: [agentWalletAddress],
});
```

### Submit a review after settlement

```typescript
await walletClient.writeContract({
  address: XCROW_ROUTER,
  abi: xcrowRouterAbi,
  functionName: "submitFeedback",
  args: [
    jobId,
    BigInt(5),     // star rating 1-5
    0,             // valueDecimals
    "rating",      // tag
    "",            // feedbackURI — IPFS URI to review JSON (optional)
    "0x0000000000000000000000000000000000000000000000000000000000000000", // feedbackHash
  ],
});
```

---

## Build and Deploy

**Requirements:** [Foundry](https://book.getfoundry.sh/getting-started/installation)

```shell
# Install dependencies
forge install

# Compile
forge build

# Run tests
forge test -vvv

# Check formatting
forge fmt --check

# Deploy to Arc Testnet
forge script script/Deploy.s.sol \
  --rpc-url $ARC_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Create a `.env` file before deploying:

```
PRIVATE_KEY=your_deployer_private_key
ARC_RPC_URL=https://rpc.testnet.arc.network
```

---

## Security

- All state-changing functions use `ReentrancyGuard`
- USDC transfers use `SafeERC20` throughout
- The Router and Escrow are independently `Pausable` for emergency stops
- `acceptJob`, `startJob`, and `completeJob` are gated to the assigned `agentWallet`
- Cancellations, rejections, and refunds are routed through the `originalClient` mapping to prevent USDC from being stranded in the Router
- `rejectJob` in the escrow has no auth check — authentication is enforced by the Router in `rejectJobViaRouter` before the call
- `CrossChainSettler.settleCrossChain` is restricted to authorised callers
- Dispute resolution is owner-arbitrated with a configurable timeout for automatic client refund
- `submitProofOfWork` can only be called by the assigned `agentWallet` and only once per job
- `autoSettle` checks that PoW was submitted and the full `settlementWindow` has elapsed; if the client disputes before the window closes, `autoSettle` is permanently blocked for that job
- ERC-8004 `giveFeedback` calls in `settleAndPay` and `autoSettleViaRouter` are wrapped in `try/catch` so a registry failure never blocks settlement

---

## License

GPL-3.0
