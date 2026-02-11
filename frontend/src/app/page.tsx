"use client";

import { useEffect, useState, useCallback } from "react";
import { useAccount } from "wagmi";
import { useXcrow, Job } from "@/hooks/useXcrow";
import { WalletStatusCard } from "@/components/WalletStatusCard";
import { HireAgentCard } from "@/components/HireAgentCard";
import { StatusBadge } from "@/components/StatusBadge";
import { formatUSDC, formatDateTime } from "@/lib/utils";

export default function DashboardPage() {
  const { isConnected, address } = useAccount();
  const { getClientJobs, getJob, settleJob, cancelJob, disputeJob, usdcBalance } = useXcrow();
  const [jobs, setJobs] = useState<Job[]>([]);
  const [loading, setLoading] = useState(false);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [balance, setBalance] = useState<bigint>(0n);

  const loadJobs = useCallback(async () => {
    if (!isConnected || !address) return;
    setLoading(true);
    try {
      const [ids, bal] = await Promise.all([getClientJobs(address), usdcBalance(address)]);
      setBalance(bal);
      const jobData = await Promise.all(ids.map((id) => getJob(id)));
      const valid = jobData.filter(Boolean) as Job[];
      valid.sort((a, b) => Number(b.createdAt - a.createdAt));
      setJobs(valid);
    } catch (e) {
      console.error("Failed to load:", e);
    } finally {
      setLoading(false);
    }
  }, [isConnected, address, getClientJobs, getJob, usdcBalance]);

  useEffect(() => {
    loadJobs();
  }, [loadJobs]);

  async function handleAction(action: string, jobId: bigint) {
    setActionLoading(`${action}-${jobId}`);
    try {
      let success = false;
      switch (action) {
        case "settle":
          success = await settleJob(jobId);
          break;
        case "cancel":
          success = await cancelJob(jobId);
          break;
        case "dispute": {
          const reason = window.prompt("Enter dispute reason:");
          if (reason) success = await disputeJob(jobId, reason);
          break;
        }
      }
      if (success) await loadJobs();
    } finally {
      setActionLoading(null);
    }
  }

  const activeJobs = jobs.filter((j) => j.status <= 3);
  const settledJobs = jobs.filter((j) => j.status === 4);
  const totalEscrowed = activeJobs.reduce((sum, j) => sum + j.amount, 0n);

  return (
    <div className="space-y-6">
      {/* Stats row */}
      {isConnected && (
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 sm:gap-4">
          <div className="glass-card stat-card">
            <div className="stat-label">Active Jobs</div>
            <div className="stat-value">{activeJobs.length}</div>
          </div>
          <div className="glass-card stat-card">
            <div className="stat-label">Settled</div>
            <div className="stat-value">{settledJobs.length}</div>
          </div>
          <div className="glass-card stat-card">
            <div className="stat-label">In Escrow</div>
            <div className="stat-value">${formatUSDC(totalEscrowed)}</div>
          </div>
          <div className="glass-card stat-card">
            <div className="stat-label">Balance</div>
            <div className="stat-value tabular-nums">${formatUSDC(balance)}</div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 sm:gap-6">
        {/* Left column: Jobs */}
        <div className="lg:col-span-2 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold" style={{ color: "#0a0a0a" }}>Recent Jobs</h2>
            <button
              onClick={loadJobs}
              disabled={loading || !isConnected}
              className="btn-ghost px-3 py-1.5 text-xs disabled:opacity-30"
            >
              {loading ? "Loading..." : "Refresh"}
            </button>
          </div>

          {!isConnected ? (
            <div className="glass-card p-12 text-center">
              <p className="text-sm" style={{ color: "#a3a3a3" }}>Connect your wallet to view jobs</p>
            </div>
          ) : loading ? (
            <div className="space-y-3">
              {[1, 2, 3].map((i) => (
                <div key={i} className="glass-card p-4">
                  <div className="skeleton w-full h-12" />
                </div>
              ))}
            </div>
          ) : jobs.length === 0 ? (
            <div className="glass-card p-12 text-center">
              <p className="text-sm" style={{ color: "#a3a3a3" }}>No jobs yet — hire an agent to get started</p>
            </div>
          ) : (
            <div className="space-y-2">
              {jobs.slice(0, 8).map((job) => (
                <div key={job.jobId.toString()} className="glass-card px-4 py-3">
                  <div className="flex items-center justify-between gap-3 flex-wrap">
                    <div className="flex items-center gap-3 min-w-0">
                      <span className="text-xs font-mono" style={{ color: "#a3a3a3" }}>#{job.jobId.toString()}</span>
                      <span className="text-sm" style={{ color: "#525252" }}>Agent #{job.agentId.toString()}</span>
                      <span className="text-sm font-medium tabular-nums" style={{ color: "#0a0a0a" }}>${formatUSDC(job.amount)}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <StatusBadge status={job.status} />
                      <JobActionButtons job={job} loading={actionLoading} onAction={handleAction} />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Right column: Wallet + Hire */}
        <div className="space-y-4">
          <WalletStatusCard />
          <HireAgentCard />
        </div>
      </div>
    </div>
  );
}

function JobActionButtons({
  job,
  loading,
  onAction,
}: {
  job: Job;
  loading: string | null;
  onAction: (action: string, jobId: bigint) => void;
}) {
  const buttons: { label: string; action: string; accent?: boolean }[] = [];

  if (job.status === 0) buttons.push({ label: "Cancel", action: "cancel" });
  if (job.status === 3) buttons.push({ label: "Settle", action: "settle", accent: true });
  if (job.status === 1 || job.status === 2 || job.status === 3) {
    buttons.push({ label: "Dispute", action: "dispute" });
  }

  if (buttons.length === 0) return null;

  return (
    <div className="flex gap-1.5">
      {buttons.map((btn) => {
        const key = `${btn.action}-${job.jobId}`;
        const isLoading = loading === key;
        return (
          <button
            key={btn.action}
            onClick={() => onAction(btn.action, job.jobId)}
            disabled={isLoading}
            className={`${btn.accent ? "btn-gradient" : "btn-ghost"} px-2 py-1 text-[10px] disabled:opacity-30`}
          >
            {isLoading ? "..." : btn.label}
          </button>
        );
      })}
    </div>
  );
}
