"use client";

import { useEffect, useState, useCallback } from "react";
import { useAccount } from "wagmi";
import { useXcrow, Job } from "@/hooks/useXcrow";
import { formatUSDC, formatDateTime } from "@/lib/utils";
import { CCTP_DOMAIN_NAMES } from "@/lib/contracts";

export default function SettlementPage() {
  const { isConnected, address } = useAccount();
  const { getClientJobs, getJob } = useXcrow();
  const [allJobs, setAllJobs] = useState<Job[]>([]);
  const [loading, setLoading] = useState(false);

  const loadJobs = useCallback(async () => {
    if (!isConnected || !address) return;
    setLoading(true);
    try {
      const ids = await getClientJobs(address);
      const jobData = await Promise.all(ids.map((id) => getJob(id)));
      setAllJobs(jobData.filter(Boolean) as Job[]);
    } catch (e) {
      console.error("Failed to load settlements:", e);
    } finally {
      setLoading(false);
    }
  }, [isConnected, address, getClientJobs, getJob]);

  useEffect(() => {
    loadJobs();
  }, [loadJobs]);

  const settled = allJobs.filter((j) => j.status === 4);
  const totalSettled = settled.reduce((sum, j) => sum + j.amount, 0n);
  const totalFees = settled.reduce((sum, j) => sum + j.platformFee, 0n);

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold" style={{ color: "#0a0a0a" }}>Settlement</h1>
          <p className="text-sm mt-0.5" style={{ color: "#a3a3a3" }}>Settled job history &amp; analytics</p>
        </div>
        <button
          onClick={loadJobs}
          disabled={loading || !isConnected}
          className="btn-ghost px-3 py-1.5 text-sm disabled:opacity-30 whitespace-nowrap"
        >
          {loading ? "Loading..." : "Refresh"}
        </button>
      </div>

      {/* Stats */}
      {isConnected && !loading && (
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4">
          <div className="glass-card stat-card">
            <div className="stat-label">Settled Jobs</div>
            <div className="stat-value">{settled.length}</div>
          </div>
          <div className="glass-card stat-card">
            <div className="stat-label">Total Settled</div>
            <div className="stat-value tabular-nums">${formatUSDC(totalSettled)}</div>
          </div>
          <div className="glass-card stat-card">
            <div className="stat-label">Fees Paid</div>
            <div className="stat-value tabular-nums">${formatUSDC(totalFees)}</div>
          </div>
        </div>
      )}

      {!isConnected ? (
        <div className="glass-card p-12 text-center">
          <p className="text-sm" style={{ color: "#a3a3a3" }}>Connect your wallet to view settlement history</p>
        </div>
      ) : loading ? (
        <div className="glass-card p-4">
          <div className="space-y-3">
            {[1, 2, 3].map((i) => <div key={i} className="skeleton w-full h-12" />)}
          </div>
        </div>
      ) : settled.length === 0 ? (
        <div className="glass-card p-12 text-center">
          <p className="text-sm" style={{ color: "#a3a3a3" }}>No settled jobs yet</p>
        </div>
      ) : (
        <div className="glass-card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="table-dark min-w-[640px]">
              <thead>
                <tr>
                  <th>Job ID</th>
                  <th>Agent</th>
                  <th>Agent Payout</th>
                  <th className="hidden sm:table-cell">Protocol Fee</th>
                  <th className="hidden md:table-cell">Route</th>
                  <th>Settled</th>
                </tr>
              </thead>
              <tbody>
                {settled.map((job) => {
                  const payout = job.amount - job.platformFee;
                  const destName =
                    CCTP_DOMAIN_NAMES[job.destinationDomain] ??
                    `Domain ${job.destinationDomain}`;
                  return (
                    <tr key={job.jobId.toString()}>
                      <td className="font-mono text-xs" style={{ color: "#0a0a0a" }}>
                        #{job.jobId.toString()}
                      </td>
                      <td style={{ color: "#0a0a0a" }}>
                        #{job.agentId.toString()}
                      </td>
                      <td className="tabular-nums font-bold" style={{ color: "#0a0a0a" }}>
                        ${formatUSDC(payout)}
                      </td>
                      <td className="hidden sm:table-cell tabular-nums" style={{ color: "#a3a3a3" }}>
                        ${formatUSDC(job.platformFee)}
                      </td>
                      <td className="hidden md:table-cell" style={{ color: "#737373" }}>
                        {job.isCrossChain ? (
                          <span>Sepolia → {destName}</span>
                        ) : (
                          "Sepolia (local)"
                        )}
                      </td>
                      <td className="text-xs" style={{ color: "#a3a3a3" }}>
                        {formatDateTime(job.settledAt)}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
