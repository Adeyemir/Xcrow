import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { ethers } from "ethers";
import { router, usdc, escrow } from "../contracts.js";
import { wallet, ADDRESSES, SEPOLIA_CHAIN_ID } from "../config.js";

export function registerHireTools(server: McpServer) {
    // --- xcrow_hire_agent ---
    server.registerTool(
        "xcrow_hire_agent",
        {
            title: "Hire Agent",
            description:
                "Hire an ERC-8004 AI agent via the Xcrow Router. Creates an escrow job with USDC deposit. " +
                "The agent must accept the job before work begins. " +
                "Amount is in USDC (e.g., 10 means 10 USDC). Deadline is seconds from now.",
            inputSchema: {
                agentId: z.number().int().positive().describe("ERC-8004 agent token ID"),
                amount: z.number().positive().describe("Payment amount in USDC (e.g., 10 for 10 USDC)"),
                taskDescription: z.string().describe("Description of the task to be performed"),
                deadlineSeconds: z
                    .number()
                    .int()
                    .positive()
                    .default(86400)
                    .describe("Deadline in seconds from now (default: 86400 = 24h)"),
            },
        },
        async ({ agentId, amount, taskDescription, deadlineSeconds }) => {
            try {
                const amountWei = ethers.parseUnits(amount.toString(), 6); // USDC has 6 decimals
                const taskHash = ethers.keccak256(ethers.toUtf8Bytes(taskDescription));
                const block = await wallet.provider!.getBlock("latest");
                const deadline = BigInt(block!.timestamp) + BigInt(deadlineSeconds);

                // Check and approve USDC if needed
                const allowance = await usdc.allowance(wallet.address, ADDRESSES.XcrowRouter);
                if (allowance < amountWei) {
                    const approveTx = await usdc.approve(ADDRESSES.XcrowRouter, ethers.MaxUint256);
                    await approveTx.wait();
                }

                const tx = await router.hireAgent(agentId, amountWei, taskHash, deadline);
                const receipt = await tx.wait();

                // Parse AgentHired event to get jobId
                const iface = new ethers.Interface([
                    "event AgentHired(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount, bool crossChain)",
                ]);
                let jobId = "unknown";
                for (const log of receipt.logs) {
                    try {
                        const parsed = iface.parseLog({ topics: log.topics as string[], data: log.data });
                        if (parsed && parsed.name === "AgentHired") {
                            jobId = parsed.args.jobId.toString();
                            break;
                        }
                    } catch {
                        continue;
                    }
                }

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify(
                                {
                                    success: true,
                                    jobId,
                                    agentId,
                                    amount: `${amount} USDC`,
                                    taskHash,
                                    deadline: deadline.toString(),
                                    txHash: receipt.hash,
                                    explorer: `https://sepolia.etherscan.io/tx/${receipt.hash}`,
                                },
                                null,
                                2
                            ),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error hiring agent: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_hire_agent_with_quote ---
    server.registerTool(
        "xcrow_hire_agent_with_quote",
        {
            title: "Hire Agent (Reputation-Quoted)",
            description:
                "Hire an agent using the reputation-weighted price quote. " +
                "The price is automatically calculated based on the agent's reputation score and base rate. " +
                "No need to specify amount — the protocol computes it.",
            inputSchema: {
                agentId: z.number().int().positive().describe("ERC-8004 agent token ID"),
                taskDescription: z.string().describe("Description of the task"),
                deadlineSeconds: z
                    .number()
                    .int()
                    .positive()
                    .default(86400)
                    .describe("Deadline in seconds from now (default: 24h)"),
            },
        },
        async ({ agentId, taskDescription, deadlineSeconds }) => {
            try {
                // Get quote first
                const quote = await router.getQuote(agentId);
                const effectiveRate = quote.effectiveRate;
                const taskHash = ethers.keccak256(ethers.toUtf8Bytes(taskDescription));
                const block = await wallet.provider!.getBlock("latest");
                const deadline = BigInt(block!.timestamp) + BigInt(deadlineSeconds);

                // Approve effective rate (not totalCost — escrow adds its own fee)
                const allowance = await usdc.allowance(wallet.address, ADDRESSES.XcrowRouter);
                if (allowance < effectiveRate) {
                    const approveTx = await usdc.approve(ADDRESSES.XcrowRouter, ethers.MaxUint256);
                    await approveTx.wait();
                }

                const tx = await router.hireAgentWithQuote(agentId, taskHash, deadline);
                const receipt = await tx.wait();

                // Parse event
                const iface = new ethers.Interface([
                    "event AgentHired(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount, bool crossChain)",
                ]);
                let jobId = "unknown";
                for (const log of receipt.logs) {
                    try {
                        const parsed = iface.parseLog({ topics: log.topics as string[], data: log.data });
                        if (parsed && parsed.name === "AgentHired") {
                            jobId = parsed.args.jobId.toString();
                            break;
                        }
                    } catch {
                        continue;
                    }
                }

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify(
                                {
                                    success: true,
                                    jobId,
                                    agentId,
                                    effectiveRate: ethers.formatUnits(effectiveRate, 6) + " USDC",
                                    totalCost: ethers.formatUnits(quote.totalCost, 6) + " USDC",
                                    reputationScore: quote.reputationScore.toString(),
                                    txHash: receipt.hash,
                                    explorer: `https://sepolia.etherscan.io/tx/${receipt.hash}`,
                                },
                                null,
                                2
                            ),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error hiring agent: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_hire_agent_cross_chain ---
    server.registerTool(
        "xcrow_hire_agent_cross_chain",
        {
            title: "Hire Agent (Cross-Chain)",
            description:
                "Hire an agent for cross-chain settlement via CCTP V2. " +
                "Use this when the agent is on a different chain. " +
                "Destination domains: 0=Ethereum, 3=Arbitrum, 6=Base, 26=Linea.",
            inputSchema: {
                agentId: z.number().int().positive().describe("ERC-8004 agent token ID"),
                amount: z.number().positive().describe("Payment amount in USDC"),
                taskDescription: z.string().describe("Task description"),
                deadlineSeconds: z.number().int().positive().default(86400).describe("Deadline in seconds from now"),
                destinationDomain: z.number().int().describe("CCTP domain ID (0=Ethereum, 3=Arbitrum, 6=Base, 26=Linea)"),
            },
        },
        async ({ agentId, amount, taskDescription, deadlineSeconds, destinationDomain }) => {
            try {
                const amountWei = ethers.parseUnits(amount.toString(), 6);
                const taskHash = ethers.keccak256(ethers.toUtf8Bytes(taskDescription));
                const block = await wallet.provider!.getBlock("latest");
                const deadline = BigInt(block!.timestamp) + BigInt(deadlineSeconds);

                const allowance = await usdc.allowance(wallet.address, ADDRESSES.XcrowRouter);
                if (allowance < amountWei) {
                    const approveTx = await usdc.approve(ADDRESSES.XcrowRouter, ethers.MaxUint256);
                    await approveTx.wait();
                }

                const tx = await router.hireAgentCrossChain(agentId, amountWei, taskHash, deadline, destinationDomain);
                const receipt = await tx.wait();

                const iface = new ethers.Interface([
                    "event AgentHired(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount, bool crossChain)",
                ]);
                let jobId = "unknown";
                for (const log of receipt.logs) {
                    try {
                        const parsed = iface.parseLog({ topics: log.topics as string[], data: log.data });
                        if (parsed && parsed.name === "AgentHired") {
                            jobId = parsed.args.jobId.toString();
                            break;
                        }
                    } catch {
                        continue;
                    }
                }

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify(
                                {
                                    success: true,
                                    jobId,
                                    agentId,
                                    amount: `${amount} USDC`,
                                    destinationDomain,
                                    crossChain: true,
                                    txHash: receipt.hash,
                                    explorer: `https://sepolia.etherscan.io/tx/${receipt.hash}`,
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
