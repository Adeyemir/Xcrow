# Xcrow MCP Server

MCP (Model Context Protocol) server for the **Xcrow Protocol** — the USDC payment layer for the ERC-8004 agent economy.

This server lets any AI assistant (Claude, GPT, Cursor, etc.) interact with Xcrow smart contracts: hire AI agents, manage job lifecycles, settle payments, and query on-chain data.

## Setup

```bash
cd mcp
npm install
npm run build
```

### Environment Variables

Create a `.env` file (or use the root `.env`):

```env
SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
PRIVATE_KEY=0x...your_private_key...
```

> **⚠️ Hot Wallet**: The `PRIVATE_KEY` signs all transactions. Fund it with Sepolia ETH (gas) and USDC (escrow deposits). Get test USDC from [Circle Faucet](https://faucet.circle.com).

## Usage

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "xcrow": {
      "command": "node",
      "args": ["/absolute/path/to/Xcrow/mcp/dist/index.js"],
      "env": {
        "PRIVATE_KEY": "0x...",
        "SEPOLIA_RPC_URL": "https://ethereum-sepolia-rpc.publicnode.com"
      }
    }
  }
}
```

### Cursor

Add to `.cursor/mcp.json` in your project:

```json
{
  "mcpServers": {
    "xcrow": {
      "command": "node",
      "args": ["./mcp/dist/index.js"],
      "env": {
        "PRIVATE_KEY": "0x...",
        "SEPOLIA_RPC_URL": "https://ethereum-sepolia-rpc.publicnode.com"
      }
    }
  }
}
```

### Dev Mode

```bash
npm run dev  # Uses tsx for hot-reload
```

## Available Tools

### Hiring
| Tool | Description |
|------|-------------|
| `xcrow_hire_agent` | Hire agent with fixed USDC amount |
| `xcrow_hire_agent_with_quote` | Hire using reputation-weighted pricing |
| `xcrow_hire_agent_cross_chain` | Hire for cross-chain CCTP settlement |

### Job Lifecycle
| Tool | Description |
|------|-------------|
| `xcrow_accept_job` | Agent accepts a job |
| `xcrow_start_job` | Agent starts work |
| `xcrow_complete_job` | Agent marks done |
| `xcrow_settle_job` | Client releases payment |
| `xcrow_settle_cross_chain` | Settle via CCTP V2 |
| `xcrow_cancel_job` | Cancel (auto-detects router jobs) |
| `xcrow_dispute_job` | Raise a dispute |
| `xcrow_approve_usdc` | Manual USDC approval |

### Read Operations
| Tool | Description |
|------|-------------|
| `xcrow_get_wallet` | MCP wallet address |
| `xcrow_get_balance` | USDC + ETH balance |
| `xcrow_get_job` | Full job details |
| `xcrow_get_my_jobs` | All jobs for this wallet |
| `xcrow_get_agent_jobs` | Jobs for an agent |
| `xcrow_get_quote` | Reputation-weighted price quote |
| `xcrow_get_agent_info` | Agent owner, wallet, URI |

### Resources
| URI | Description |
|-----|-------------|
| `xcrow://protocol` | Contract addresses, chain info, fees |
| `xcrow://statuses` | Job lifecycle states |

## Example Conversation

> **You**: Hire agent #1 to process my data for 10 USDC  
> **AI**: *calls `xcrow_hire_agent`* → Job #5 created! Tx: 0x...  
> **You**: What's the status?  
> **AI**: *calls `xcrow_get_job`* → Job #5: Created, waiting for agent to accept.
