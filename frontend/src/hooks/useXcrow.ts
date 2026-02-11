"use client";

import { useCallback } from "react";
import { usePublicClient, useWalletClient, useAccount } from "wagmi";
import { keccak256, toHex, maxUint256, parseAbiItem } from "viem";
import toast from "react-hot-toast";
import { ADDRESSES } from "@/lib/contracts";
import { explorerTxLink } from "@/lib/utils";
import XcrowEscrowABI from "@/lib/abis/XcrowEscrow.json";
import XcrowRouterABI from "@/lib/abis/XcrowRouter.json";
import ReputationPricerABI from "@/lib/abis/ReputationPricer.json";
import IdentityRegistryABI from "@/lib/abis/IdentityRegistry.json";
import ERC20ABI from "@/lib/abis/ERC20.json";

export interface Job {
  jobId: bigint;
  agentId: bigint;
  agentChainId: number;
  client: string;
  agentWallet: string;
  amount: bigint;
  platformFee: bigint;
  taskHash: string;
  deadline: bigint;
  createdAt: bigint;
  settledAt: bigint;
  status: number;
  isCrossChain: boolean;
  destinationDomain: number;
}

export interface PriceQuote {
  agentId: bigint;
  baseRate: bigint;
  effectiveRate: bigint;
  reputationScore: bigint;
  multiplier: bigint;
  platformFee: bigint;
  totalCost: bigint;
  quotedAt: bigint;
}

export function useXcrow() {
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  const { address } = useAccount();

  // ---- Writes (with toast) ----

  async function sendTx(
    label: string,
    fn: () => Promise<`0x${string}`>
  ): Promise<boolean> {
    if (!publicClient) return false;
    const id = toast.loading(`${label}...`);
    try {
      const hash = await fn();
      toast.loading("Waiting for confirmation...", { id });
      await publicClient.waitForTransactionReceipt({
        hash,
        timeout: 120_000, // 2 min timeout
      });
      toast.success(`${label} confirmed. ${explorerTxLink(hash)}`, {
        id,
        duration: 6000,
      });
      return true;
    } catch (e: unknown) {
      const msg =
        e instanceof Error
          ? (e as { shortMessage?: string }).shortMessage ?? e.message
          : "Transaction failed";
      toast.error(msg, { id, duration: 6000 });
      return false;
    }
  }

  // ---- Reads ----

  const getJob = useCallback(
    async (jobId: bigint): Promise<Job | null> => {
      if (!publicClient) return null;
      const job = await publicClient.readContract({
        address: ADDRESSES.XcrowEscrow as `0x${string}`,
        abi: XcrowEscrowABI,
        functionName: "getJob",
        args: [jobId],
      });
      return job as Job;
    },
    [publicClient]
  );

  const getClientJobs = useCallback(
    async (clientAddress?: string): Promise<bigint[]> => {
      if (!publicClient) return [];
      const addr = (clientAddress ?? address) as `0x${string}` | undefined;
      if (!addr) return [];

      // Get jobs from two sources:
      // 1. Old Router-created jobs: AgentHired events from XcrowRouter
      // 2. New direct jobs: JobCreated events from XcrowEscrow
      const [routerLogs, escrowLogs] = await Promise.all([
        publicClient.getLogs({
          address: ADDRESSES.XcrowRouter as `0x${string}`,
          event: parseAbiItem(
            "event AgentHired(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount, bool crossChain)"
          ),
          args: { client: addr },
          fromBlock: 10216820n,
          toBlock: "latest",
        }),
        publicClient.getLogs({
          address: ADDRESSES.XcrowEscrow as `0x${string}`,
          event: parseAbiItem(
            "event JobCreated(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount)"
          ),
          args: { client: addr },
          fromBlock: 10216820n,
          toBlock: "latest",
        }),
      ]);

      const routerJobIds = routerLogs.map((log) => log.args.jobId as bigint);
      const escrowJobIds = escrowLogs.map((log) => log.args.jobId as bigint);

      // Combine and deduplicate
      const allIds = [...new Set([...routerJobIds, ...escrowJobIds])];
      return allIds.sort((a, b) => Number(a - b));
    },
    [publicClient, address]
  );

  const getAgentJobs = useCallback(
    async (agentId: bigint): Promise<bigint[]> => {
      if (!publicClient) return [];
      const ids = await publicClient.readContract({
        address: ADDRESSES.XcrowEscrow as `0x${string}`,
        abi: XcrowEscrowABI,
        functionName: "getAgentJobs",
        args: [agentId],
      });
      return ids as bigint[];
    },
    [publicClient]
  );

  const getQuote = useCallback(
    async (agentId: bigint): Promise<PriceQuote | null> => {
      if (!publicClient) return null;
      const quote = await publicClient.readContract({
        address: ADDRESSES.XcrowRouter as `0x${string}`,
        abi: XcrowRouterABI,
        functionName: "getQuote",
        args: [agentId],
      });
      return quote as PriceQuote;
    },
    [publicClient]
  );

  const getAgentInfo = useCallback(
    async (agentId: bigint) => {
      if (!publicClient) return null;
      const result = await publicClient.readContract({
        address: ADDRESSES.XcrowRouter as `0x${string}`,
        abi: XcrowRouterABI,
        functionName: "getAgentInfo",
        args: [agentId],
      }) as [string, string, string];
      return { owner: result[0], wallet: result[1], uri: result[2] };
    },
    [publicClient]
  );

  const getAgentBaseRate = useCallback(
    async (agentId: bigint): Promise<bigint> => {
      if (!publicClient) return 0n;
      const rate = await publicClient.readContract({
        address: ADDRESSES.ReputationPricer as `0x${string}`,
        abi: ReputationPricerABI,
        functionName: "agentBaseRates",
        args: [agentId],
      });
      return rate as bigint;
    },
    [publicClient]
  );

  const getReputationMultiplier = useCallback(
    async (agentId: bigint): Promise<{ score: bigint; multiplierBps: bigint }> => {
      if (!publicClient) return { score: 0n, multiplierBps: 10000n };
      const result = await publicClient.readContract({
        address: ADDRESSES.ReputationPricer as `0x${string}`,
        abi: ReputationPricerABI,
        functionName: "getReputationMultiplier",
        args: [agentId],
      }) as [bigint, bigint];
      return { score: result[0], multiplierBps: result[1] };
    },
    [publicClient]
  );

  const usdcBalance = useCallback(
    async (addr?: string): Promise<bigint> => {
      if (!publicClient) return 0n;
      const target = (addr ?? address) as `0x${string}` | undefined;
      if (!target) return 0n;
      const bal = await publicClient.readContract({
        address: ADDRESSES.USDC as `0x${string}`,
        abi: ERC20ABI,
        functionName: "balanceOf",
        args: [target],
      });
      return bal as bigint;
    },
    [publicClient, address]
  );

  const usdcAllowance = useCallback(
    async (owner: string, spender: string): Promise<bigint> => {
      if (!publicClient) return 0n;
      const allowance = await publicClient.readContract({
        address: ADDRESSES.USDC as `0x${string}`,
        abi: ERC20ABI,
        functionName: "allowance",
        args: [owner as `0x${string}`, spender as `0x${string}`],
      });
      return allowance as bigint;
    },
    [publicClient]
  );

  const getTokenURI = useCallback(
    async (agentId: bigint): Promise<string> => {
      if (!publicClient) return "";
      const uri = await publicClient.readContract({
        address: ADDRESSES.IdentityRegistry as `0x${string}`,
        abi: IdentityRegistryABI,
        functionName: "tokenURI",
        args: [agentId],
      });
      return uri as string;
    },
    [publicClient]
  );

  const estimateCrossChainFee = useCallback(
    async (amount: bigint, destinationDomain: number): Promise<bigint> => {
      if (!publicClient) return 0n;
      const fee = await publicClient.readContract({
        address: ADDRESSES.XcrowRouter as `0x${string}`,
        abi: XcrowRouterABI,
        functionName: "estimateCrossChainFee",
        args: [amount, destinationDomain],
      });
      return fee as bigint;
    },
    [publicClient]
  );

  // ---- Writes ----

  const approveUSDC = useCallback(
    async (spender: string, amount: bigint) => {
      if (!walletClient) return false;
      return sendTx("Approving USDC", () =>
        walletClient.writeContract({
          address: ADDRESSES.USDC as `0x${string}`,
          abi: ERC20ABI,
          functionName: "approve",
          args: [spender as `0x${string}`, amount],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const hireAgent = useCallback(
    async (agentId: bigint, amount: bigint, taskHash: string, deadline: bigint) => {
      if (!walletClient || !address) return false;

      try {
        // Call escrow.createJob directly so job.client = user's wallet (not router)
        const allowance = await usdcAllowance(address, ADDRESSES.XcrowEscrow);
        if (allowance < amount) {
          const ok = await approveUSDC(ADDRESSES.XcrowEscrow, maxUint256);
          if (!ok) return false;
        }

        return await sendTx("Hiring agent", () =>
          walletClient.writeContract({
            address: ADDRESSES.XcrowEscrow as `0x${string}`,
            abi: XcrowEscrowABI,
            functionName: "createJob",
            args: [agentId, 11155111, amount, taskHash as `0x${string}`, deadline],
          })
        );
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : "Failed to hire agent";
        toast.error(msg, { duration: 6000 });
        return false;
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient, address, usdcAllowance, approveUSDC]
  );

  const hireAgentWithQuote = useCallback(
    async (agentId: bigint, taskHash: string, deadline: bigint) => {
      if (!walletClient || !address) return false;

      try {
        const quote = await getQuote(agentId);
        if (!quote) return false;

        // Contract only pulls effectiveRate (not totalCost) — escrow adds its own fee
        const allowance = await usdcAllowance(address, ADDRESSES.XcrowRouter);
        if (allowance < quote.effectiveRate) {
          const ok = await approveUSDC(ADDRESSES.XcrowRouter, maxUint256);
          if (!ok) return false;
        }

        return await sendTx("Hiring agent (quoted)", () =>
          walletClient.writeContract({
            address: ADDRESSES.XcrowRouter as `0x${string}`,
            abi: XcrowRouterABI,
            functionName: "hireAgentWithQuote",
            args: [agentId, taskHash as `0x${string}`, deadline],
          })
        );
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : "Failed to hire agent";
        toast.error(msg, { duration: 6000 });
        return false;
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient, address, getQuote, usdcAllowance, approveUSDC]
  );

  const acceptJob = useCallback(
    async (jobId: bigint) => {
      if (!walletClient) return false;
      return sendTx("Accepting job", () =>
        walletClient.writeContract({
          address: ADDRESSES.XcrowEscrow as `0x${string}`,
          abi: XcrowEscrowABI,
          functionName: "acceptJob",
          args: [jobId],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const startJob = useCallback(
    async (jobId: bigint) => {
      if (!walletClient) return false;
      return sendTx("Starting job", () =>
        walletClient.writeContract({
          address: ADDRESSES.XcrowEscrow as `0x${string}`,
          abi: XcrowEscrowABI,
          functionName: "startJob",
          args: [jobId],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const completeJob = useCallback(
    async (jobId: bigint) => {
      if (!walletClient) return false;
      return sendTx("Completing job", () =>
        walletClient.writeContract({
          address: ADDRESSES.XcrowEscrow as `0x${string}`,
          abi: XcrowEscrowABI,
          functionName: "completeJob",
          args: [jobId],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const settleJob = useCallback(
    async (jobId: bigint) => {
      if (!walletClient) return false;
      return sendTx("Settling job", () =>
        walletClient.writeContract({
          address: ADDRESSES.XcrowEscrow as `0x${string}`,
          abi: XcrowEscrowABI,
          functionName: "settleJob",
          args: [jobId],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const cancelJob = useCallback(
    async (jobId: bigint) => {
      if (!walletClient || !publicClient) return false;

      try {
        // Check if this is a Router-created job
        const job = await getJob(jobId);
        if (!job) throw new Error("Job not found");

        const isRouterJob = job.client.toLowerCase() === ADDRESSES.XcrowRouter.toLowerCase();

        if (isRouterJob) {
          return sendTx("Cancelling job via Router", () =>
            walletClient.writeContract({
              address: ADDRESSES.XcrowRouter as `0x${string}`,
              abi: XcrowRouterABI,
              functionName: "cancelJobViaRouter",
              args: [jobId],
            })
          );
        } else {
          return sendTx("Cancelling job", () =>
            walletClient.writeContract({
              address: ADDRESSES.XcrowEscrow as `0x${string}`,
              abi: XcrowEscrowABI,
              functionName: "cancelJob",
              args: [jobId],
            })
          );
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : "Failed to cancel job";
        toast.error(msg, { duration: 6000 });
        return false;
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient, getJob]
  );

  const disputeJob = useCallback(
    async (jobId: bigint, reason: string) => {
      if (!walletClient || !publicClient) return false;

      try {
        // Check if this is a Router-created job
        const job = await getJob(jobId);
        if (!job) throw new Error("Job not found");

        const isRouterJob = job.client.toLowerCase() === ADDRESSES.XcrowRouter.toLowerCase();

        if (isRouterJob) {
          return sendTx("Disputing job via Router", () =>
            walletClient.writeContract({
              address: ADDRESSES.XcrowRouter as `0x${string}`,
              abi: XcrowRouterABI,
              functionName: "disputeJobViaRouter",
              args: [jobId, reason],
            })
          );
        } else {
          return sendTx("Disputing job", () =>
            walletClient.writeContract({
              address: ADDRESSES.XcrowEscrow as `0x${string}`,
              abi: XcrowEscrowABI,
              functionName: "disputeJob",
              args: [jobId, reason],
            })
          );
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : "Failed to dispute job";
        toast.error(msg, { duration: 6000 });
        return false;
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient, getJob]
  );

  const refundExpiredJob = useCallback(
    async (jobId: bigint) => {
      if (!walletClient) return false;
      return sendTx("Refunding expired job", () =>
        walletClient.writeContract({
          address: ADDRESSES.XcrowEscrow as `0x${string}`,
          abi: XcrowEscrowABI,
          functionName: "refundExpiredJob",
          args: [jobId],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const resolveDispute = useCallback(
    async (jobId: bigint) => {
      if (!walletClient) return false;
      return sendTx("Resolving dispute", () =>
        walletClient.writeContract({
          address: ADDRESSES.XcrowEscrow as `0x${string}`,
          abi: XcrowEscrowABI,
          functionName: "resolveDispute",
          args: [jobId],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const settleAndPayViaRouter = useCallback(
    async (jobId: bigint, destinationDomain: number, hookData: string) => {
      if (!walletClient) return false;
      return sendTx("Settling & paying via Router", () =>
        walletClient.writeContract({
          address: ADDRESSES.XcrowRouter as `0x${string}`,
          abi: XcrowRouterABI,
          functionName: "settleAndPay",
          args: [jobId, destinationDomain, hookData as `0x${string}`],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const submitFeedbackViaRouter = useCallback(
    async (jobId: bigint, value: bigint, valueDecimals: number, tag: string, uri: string, hash: string) => {
      if (!walletClient) return false;
      return sendTx("Submitting feedback", () =>
        walletClient.writeContract({
          address: ADDRESSES.XcrowRouter as `0x${string}`,
          abi: XcrowRouterABI,
          functionName: "submitFeedback",
          args: [jobId, value, valueDecimals, tag, uri, hash as `0x${string}`],
        })
      );
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient]
  );

  const hireAgentCrossChain = useCallback(
    async (agentId: bigint, amount: bigint, taskHash: string, deadline: bigint, destinationDomain: number) => {
      if (!walletClient || !address) return false;

      try {
        const allowance = await usdcAllowance(address, ADDRESSES.XcrowRouter);
        if (allowance < amount) {
          const ok = await approveUSDC(ADDRESSES.XcrowRouter, maxUint256);
          if (!ok) return false;
        }

        return await sendTx("Hiring agent (cross-chain)", () =>
          walletClient.writeContract({
            address: ADDRESSES.XcrowRouter as `0x${string}`,
            abi: XcrowRouterABI,
            functionName: "hireAgentCrossChain",
            args: [agentId, amount, taskHash as `0x${string}`, deadline, destinationDomain],
          })
        );
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : "Failed to hire agent cross-chain";
        toast.error(msg, { duration: 6000 });
        return false;
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletClient, publicClient, address, usdcAllowance, approveUSDC]
  );

  return {
    // reads
    getJob,
    getClientJobs,
    getAgentJobs,
    getQuote,
    getAgentInfo,
    getAgentBaseRate,
    getReputationMultiplier,
    usdcBalance,
    usdcAllowance,
    getTokenURI,
    estimateCrossChainFee,
    // writes
    approveUSDC,
    hireAgent,
    hireAgentWithQuote,
    hireAgentCrossChain,
    acceptJob,
    startJob,
    completeJob,
    settleJob,
    cancelJob,
    disputeJob,
    refundExpiredJob,
    resolveDispute,
    settleAndPayViaRouter,
    submitFeedbackViaRouter,
  };
}

export function makeTaskHash(seed: string): `0x${string}` {
  return keccak256(toHex(seed));
}
