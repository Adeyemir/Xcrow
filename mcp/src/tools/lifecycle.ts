import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { ethers } from "ethers";
import { escrow, router, usdc } from "../contracts.js";
import { wallet, ADDRESSES } from "../config.js";

export function registerLifecycleTools(server: McpServer) {
    // --- xcrow_accept_job ---
    server.registerTool(
        "xcrow_accept_job",
        {
            title: "Accept Job",
            description: "Agent accepts a job offer. Only the assigned agent wallet can call this.",
            inputSchema: {
                jobId: z.number().int().nonnegative().describe("Job ID to accept"),
            },
        },
        async ({ jobId }) => {
            try {
                const tx = await escrow.acceptJob(jobId);
                const receipt = await tx.wait();
                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({ success: true, jobId, action: "accepted", txHash: receipt.hash }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error accepting job: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_start_job ---
    server.registerTool(
        "xcrow_start_job",
        {
            title: "Start Job",
            description: "Agent marks a job as in-progress. Must be in Accepted status.",
            inputSchema: {
                jobId: z.number().int().nonnegative().describe("Job ID to start"),
            },
        },
        async ({ jobId }) => {
            try {
                const tx = await escrow.startJob(jobId);
                const receipt = await tx.wait();
                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({ success: true, jobId, action: "started", txHash: receipt.hash }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error starting job: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_complete_job ---
    server.registerTool(
        "xcrow_complete_job",
        {
            title: "Complete Job",
            description: "Agent marks a job as completed. Client can then settle and release payment.",
            inputSchema: {
                jobId: z.number().int().nonnegative().describe("Job ID to complete"),
            },
        },
        async ({ jobId }) => {
            try {
                const tx = await escrow.completeJob(jobId);
                const receipt = await tx.wait();
                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({ success: true, jobId, action: "completed", txHash: receipt.hash }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error completing job: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_settle_job ---
    server.registerTool(
        "xcrow_settle_job",
        {
            title: "Settle Job",
            description:
                "Client settles a completed job, releasing payment to the agent. " +
                "A 2.5% protocol fee is deducted automatically.",
            inputSchema: {
                jobId: z.number().int().nonnegative().describe("Job ID to settle"),
            },
        },
        async ({ jobId }) => {
            try {
                const tx = await escrow.settleJob(jobId);
                const receipt = await tx.wait();
                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({ success: true, jobId, action: "settled", txHash: receipt.hash }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error settling job: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_settle_cross_chain ---
    server.registerTool(
        "xcrow_settle_cross_chain",
        {
            title: "Settle Job (Cross-Chain)",
            description:
                "Settle a job and send payment cross-chain via CCTP V2. " +
                "The agent receives USDC on their destination chain.",
            inputSchema: {
                jobId: z.number().int().nonnegative().describe("Job ID to settle"),
                destinationDomain: z.number().int().describe("CCTP domain (0=Ethereum, 3=Arbitrum, 6=Base, 26=Linea)"),
            },
        },
        async ({ jobId, destinationDomain }) => {
            try {
                const tx = await router.settleAndPay(jobId, destinationDomain, "0x");
                const receipt = await tx.wait();
                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({
                                success: true,
                                jobId,
                                action: "settled_cross_chain",
                                destinationDomain,
                                txHash: receipt.hash,
                            }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error settling cross-chain: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_cancel_job ---
    server.registerTool(
        "xcrow_cancel_job",
        {
            title: "Cancel Job",
            description:
                "Cancel a job and get a full USDC refund. " +
                "Auto-detects whether the job was created via the Router and uses the correct cancellation method.",
            inputSchema: {
                jobId: z.number().int().nonnegative().describe("Job ID to cancel"),
            },
        },
        async ({ jobId }) => {
            try {
                // Check if this is a router-created job
                const job = await escrow.getJob(jobId);
                const isRouterJob = job.client.toLowerCase() === ADDRESSES.XcrowRouter.toLowerCase();

                let tx;
                if (isRouterJob) {
                    tx = await router.cancelJobViaRouter(jobId);
                } else {
                    tx = await escrow.cancelJob(jobId);
                }
                const receipt = await tx.wait();

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({
                                success: true,
                                jobId,
                                action: "cancelled",
                                viaRouter: isRouterJob,
                                refundAmount: ethers.formatUnits(job.amount, 6) + " USDC",
                                txHash: receipt.hash,
                            }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error cancelling job: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_dispute_job ---
    server.registerTool(
        "xcrow_dispute_job",
        {
            title: "Dispute Job",
            description:
                "Raise a dispute on a job. Both client and agent can dispute. " +
                "Auto-detects router-created jobs. After dispute, resolution is via timeout or arbitration.",
            inputSchema: {
                jobId: z.number().int().nonnegative().describe("Job ID to dispute"),
                reason: z.string().min(1).describe("Human-readable reason for the dispute"),
            },
        },
        async ({ jobId, reason }) => {
            try {
                const job = await escrow.getJob(jobId);
                const isRouterJob = job.client.toLowerCase() === ADDRESSES.XcrowRouter.toLowerCase();

                let tx;
                if (isRouterJob) {
                    tx = await router.disputeJobViaRouter(jobId, reason);
                } else {
                    tx = await escrow.disputeJob(jobId, reason);
                }
                const receipt = await tx.wait();

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({
                                success: true,
                                jobId,
                                action: "disputed",
                                viaRouter: isRouterJob,
                                reason,
                                txHash: receipt.hash,
                            }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error disputing job: ${msg}` }], isError: true };
            }
        }
    );

    // --- xcrow_approve_usdc ---
    server.registerTool(
        "xcrow_approve_usdc",
        {
            title: "Approve USDC",
            description:
                "Approve a contract to spend USDC on behalf of the MCP wallet. " +
                "Usually not needed — hire tools auto-approve. Use this for manual control.",
            inputSchema: {
                spender: z.enum(["escrow", "router"]).describe("Which contract to approve: 'escrow' or 'router'"),
                amount: z
                    .number()
                    .positive()
                    .optional()
                    .describe("Amount in USDC to approve (omit for unlimited)"),
            },
        },
        async ({ spender, amount }) => {
            try {
                const spenderAddress = spender === "escrow" ? ADDRESSES.XcrowEscrow : ADDRESSES.XcrowRouter;
                const approveAmount = amount ? ethers.parseUnits(amount.toString(), 6) : ethers.MaxUint256;

                const tx = await usdc.approve(spenderAddress, approveAmount);
                const receipt = await tx.wait();

                return {
                    content: [
                        {
                            type: "text" as const,
                            text: JSON.stringify({
                                success: true,
                                spender,
                                spenderAddress,
                                amount: amount ? `${amount} USDC` : "unlimited",
                                txHash: receipt.hash,
                            }),
                        },
                    ],
                };
            } catch (error: unknown) {
                const msg = error instanceof Error ? error.message : "Unknown error";
                return { content: [{ type: "text" as const, text: `Error approving USDC: ${msg}` }], isError: true };
            }
        }
    );
}
