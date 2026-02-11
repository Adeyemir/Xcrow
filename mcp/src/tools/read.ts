import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { ethers } from "ethers";
import { escrow, router, usdc, pricer } from "../contracts.js";
import { wallet, ADDRESSES, JOB_STATUS_LABELS, CCTP_DOMAINS } from "../config.js";

export function registerReadTools(server: McpServer) {
    // --- xcrow_get_wallet ---
    server.registerTool(
        "xcrow_get_wallet",
        {
            title: "Get MCP Wallet",
            description: "Returns the wallet address used by this MCP server for all transactions.",
            inputSchema: {},
        },
        async () => {
            return {
                content: [
                    {
                        type: "text" as const,
                        text: JSON.stringify({
                            address: wallet.address,
                            chain: "Ethereum Sepolia (11155111)",
                            note: "Fund this address with Sepolia ETH (gas) and USDC (escrow deposits)",
                        }),
                    },
                ],
            };
        }
    );

    // --- xcrow_get_balance ---
    server.registerTool(
        "xcrow_get_balance",
        {
            title: "Get USDC Balance",
            description: "Check the USDC balance of an address. Defaults to the MCP wallet.",
            inputSchema: {
                address: z.string().optional().describe("Address to check (defaults to MCP wallet)"),
            },
        },
        async ({ address }) => {
            try {
                const target = address || wallet.address;
                const balance = await usdc.balanceOf(target);
                const ethBalance = await wallet.provider!.getBalance(target);

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({
                                address: target,
                                usdc: ethers.formatUnits(balance, 6) + " USDC",
                                eth: ethers.formatEther(ethBalance) + " ETH",
                                usdcRaw: balance.toString(),
                            }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_get_job ---
    server.registerTool(
        "xcrow_get_job",
        {
            title: "Get Job Details",
            description:
                "Get full details of a job by ID, including status, amount, client, agent, deadline, and timestamps.",
            inputSchema: {
                jobId: z.number().int().nonnegative().describe("Job ID to look up"),
            },
        },
        async ({ jobId }) => {
            try {
                const job = await escrow.getJob(jobId);

                // Check if this is a router job
                let originalClient = null;
                try {
                    const oc = await router.originalClient(jobId);
                    if (oc !== ethers.ZeroAddress) originalClient = oc;
                } catch {
                    // Not a router job
                }

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify(
                                {
                                    jobId,
                                    agentId: job.agentId.toString(),
                                    client: job.client,
                                    originalClient,
                                    agentWallet: job.agentWallet,
                                    amount: ethers.formatUnits(job.amount, 6) + " USDC",
                                    platformFee: ethers.formatUnits(job.platformFee, 6) + " USDC",
                                    status: JOB_STATUS_LABELS[Number(job.status)] || `Unknown(${job.status})`,
                                    statusCode: Number(job.status),
                                    taskHash: job.taskHash,
                                    deadline: new Date(Number(job.deadline) * 1000).toISOString(),
                                    createdAt: new Date(Number(job.createdAt) * 1000).toISOString(),
                                    settledAt: Number(job.settledAt) > 0 ? new Date(Number(job.settledAt) * 1000).toISOString() : null,
                                    isCrossChain: job.isCrossChain,
                                    destinationDomain: job.isCrossChain
                                        ? `${job.destinationDomain} (${CCTP_DOMAINS[Number(job.destinationDomain)] || "Unknown"})`
                                        : null,
                                    isRouterJob: originalClient !== null,
                                },
                                null,
                                2
                            ),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_get_my_jobs ---
    server.registerTool(
        "xcrow_get_my_jobs",
        {
            title: "Get My Jobs",
            description:
                "List all jobs created by the MCP wallet. Scans both Router (AgentHired) and Escrow (JobCreated) events.",
            inputSchema: {},
        },
        async () => {
            try {
                // Scan recent blocks for events
                const currentBlock = await wallet.provider!.getBlockNumber();
                const fromBlock = Math.max(0, currentBlock - 100000); // Last ~100k blocks

                const routerIface = new ethers.Interface([
                    "event AgentHired(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount, bool crossChain)",
                ]);
                const escrowIface = new ethers.Interface([
                    "event JobCreated(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount)",
                ]);

                const [routerLogs, escrowLogs] = await Promise.all([
                    wallet.provider!.getLogs({
                        address: ADDRESSES.XcrowRouter,
                        topics: [
                            routerIface.getEvent("AgentHired")!.topicHash,
                            null,
                            null,
                            ethers.zeroPadValue(wallet.address, 32),
                        ],
                        fromBlock,
                        toBlock: "latest",
                    }),
                    wallet.provider!.getLogs({
                        address: ADDRESSES.XcrowEscrow,
                        topics: [
                            escrowIface.getEvent("JobCreated")!.topicHash,
                            null,
                            null,
                            ethers.zeroPadValue(wallet.address, 32),
                        ],
                        fromBlock,
                        toBlock: "latest",
                    }),
                ]);

                const jobIds = new Set<string>();
                for (const log of routerLogs) {
                    const parsed = routerIface.parseLog({ topics: log.topics as string[], data: log.data });
                    if (parsed) jobIds.add(parsed.args.jobId.toString());
                }
                for (const log of escrowLogs) {
                    const parsed = escrowIface.parseLog({ topics: log.topics as string[], data: log.data });
                    if (parsed) jobIds.add(parsed.args.jobId.toString());
                }

                // Fetch details for each job
                const jobs = [];
                for (const id of jobIds) {
                    try {
                        const job = await escrow.getJob(id);
                        jobs.push({
                            jobId: id,
                            agentId: job.agentId.toString(),
                            amount: ethers.formatUnits(job.amount, 6) + " USDC",
                            status: JOB_STATUS_LABELS[Number(job.status)] || `Unknown(${job.status})`,
                            deadline: new Date(Number(job.deadline) * 1000).toISOString(),
                        });
                    } catch {
                        jobs.push({ jobId: id, error: "Could not fetch details" });
                    }
                }

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({ wallet: wallet.address, totalJobs: jobs.length, jobs }, null, 2),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_get_agent_jobs ---
    server.registerTool(
        "xcrow_get_agent_jobs",
        {
            title: "Get Agent Jobs",
            description: "List all jobs assigned to a specific agent by their ERC-8004 token ID.",
            inputSchema: {
                agentId: z.number().int().positive().describe("ERC-8004 agent token ID"),
            },
        },
        async ({ agentId }) => {
            try {
                const jobIds: bigint[] = await escrow.getAgentJobs(agentId);
                const jobs = [];

                for (const id of jobIds) {
                    try {
                        const job = await escrow.getJob(id);
                        jobs.push({
                            jobId: id.toString(),
                            amount: ethers.formatUnits(job.amount, 6) + " USDC",
                            status: JOB_STATUS_LABELS[Number(job.status)] || `Unknown(${job.status})`,
                            client: job.client,
                        });
                    } catch {
                        jobs.push({ jobId: id.toString(), error: "Could not fetch" });
                    }
                }

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({ agentId, totalJobs: jobs.length, jobs }, null, 2),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_get_quote ---
    server.registerTool(
        "xcrow_get_quote",
        {
            title: "Get Agent Price Quote",
            description:
                "Get a reputation-weighted price quote for an agent. " +
                "Shows the base rate, reputation multiplier, effective rate, platform fee, and total cost.",
            inputSchema: {
                agentId: z.number().int().positive().describe("ERC-8004 agent token ID"),
            },
        },
        async ({ agentId }) => {
            try {
                const quote = await router.getQuote(agentId);

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify(
                                {
                                    agentId,
                                    baseRate: ethers.formatUnits(quote.baseRate, 6) + " USDC",
                                    effectiveRate: ethers.formatUnits(quote.effectiveRate, 6) + " USDC",
                                    reputationScore: quote.reputationScore.toString(),
                                    multiplier: (Number(quote.multiplier) / 10000).toFixed(2) + "x",
                                    platformFee: ethers.formatUnits(quote.platformFee, 6) + " USDC",
                                    totalCost: ethers.formatUnits(quote.totalCost, 6) + " USDC",
                                },
                                null,
                                2
                            ),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_get_agent_info ---
    server.registerTool(
        "xcrow_get_agent_info",
        {
            title: "Get Agent Info",
            description: "Get agent details from ERC-8004: owner address, wallet address, and metadata URI.",
            inputSchema: {
                agentId: z.number().int().positive().describe("ERC-8004 agent token ID"),
            },
        },
        async ({ agentId }) => {
            try {
                const result = await router.getAgentInfo(agentId);

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify(
                                {
                                    agentId,
                                    owner: result[0],
                                    wallet: result[1],
                                    metadataURI: result[2],
                                },
                                null,
                                2
                            ),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error: ${msg}` }], isError: true };
            }
        }
    );
}
