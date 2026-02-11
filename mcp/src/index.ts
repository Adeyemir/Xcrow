import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { ADDRESSES, CCTP_DOMAINS, JOB_STATUS_LABELS, wallet } from "./config.js";
import { registerHireTools } from "./tools/hire.js";
import { registerLifecycleTools } from "./tools/lifecycle.js";
import { registerReadTools } from "./tools/read.js";

// Create MCP server
const server = new McpServer({
    name: "xcrow",
    version: "1.0.0",
});

// --- Register Resources ---

server.registerResource(
    "protocol-info",
    "xcrow://protocol",
    {
        title: "Xcrow Protocol Info",
        description: "Contract addresses, chain configuration, and fee structure",
        mimeType: "application/json",
    },
    async () => ({
        contents: [
            {
                uri: "xcrow://protocol",
                text: JSON.stringify(
                    {
                        name: "Xcrow Protocol",
                        description: "USDC payment layer for the ERC-8004 agent economy",
                        chain: "Ethereum Sepolia",
                        chainId: 11155111,
                        contracts: ADDRESSES,
                        mcpWallet: wallet.address,
                        protocolFee: "2.5%",
                        cctpDomains: CCTP_DOMAINS,
                        links: {
                            explorer: "https://sepolia.etherscan.io",
                            usdcFaucet: "https://faucet.circle.com",
                        },
                    },
                    null,
                    2
                ),
            },
        ],
    })
);

server.registerResource(
    "job-statuses",
    "xcrow://statuses",
    {
        title: "Job Status Reference",
        description: "Job lifecycle states and valid transitions",
        mimeType: "application/json",
    },
    async () => ({
        contents: [
            {
                uri: "xcrow://statuses",
                text: JSON.stringify(
                    {
                        statuses: JOB_STATUS_LABELS,
                        lifecycle: {
                            Created: {
                                description: "Job created, USDC deposited in escrow. Waiting for agent to accept.",
                                transitions: ["Accepted", "Cancelled"],
                            },
                            Accepted: {
                                description: "Agent accepted the job. Can start work or be cancelled by client.",
                                transitions: ["InProgress", "Expired"],
                            },
                            InProgress: {
                                description: "Agent is actively working on the task.",
                                transitions: ["Completed", "Disputed"],
                            },
                            Completed: {
                                description: "Agent marked work as done. Client can settle or dispute.",
                                transitions: ["Settled", "Disputed"],
                            },
                            Settled: {
                                description: "Payment released to agent (minus 2.5% protocol fee). Final state.",
                                transitions: [],
                            },
                            Disputed: {
                                description: "Either party raised a dispute. Resolved by timeout or arbitration.",
                                transitions: ["Settled", "Cancelled"],
                            },
                            Cancelled: {
                                description: "Job cancelled, full USDC refund to client. Final state.",
                                transitions: [],
                            },
                            Expired: {
                                description: "Deadline passed without completion. Client can claim refund.",
                                transitions: [],
                            },
                        },
                    },
                    null,
                    2
                ),
            },
        ],
    })
);

// --- Register all tools ---
registerHireTools(server);
registerLifecycleTools(server);
registerReadTools(server);

// --- Start server via stdio ---
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}

main().catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
});
