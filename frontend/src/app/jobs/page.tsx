"use client";

import { useEffect, useState, useCallback } from "react";
import { useAccount } from "wagmi";
import { useXcrow, Job } from "@/hooks/useXcrow";
import { StatusBadge } from "@/components/StatusBadge";
import { formatUSDC, formatDateTime } from "@/lib/utils";

export default function JobsPage() {
  const { isConnected, address } = useAccount();
  const { getClientJobs, getJob, settleJob, cancelJob, disputeJob } = useXcrow();
  const [jobs, setJobs] = useState<Job[]>([]);
  const [loading, setLoading] = useState(false);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const loadJobs = useCallback(async () => {
    if (!isConnected || !address) return;
    setLoading(true);
    try {
      const ids = await getClientJobs(address);
      const jobData = await Promise.all(ids.map((id) => getJob(id)));
      const valid = jobData.filter(Boolean) as Job[];
      valid.sort((a, b) => Number(b.createdAt - a.createdAt));
      setJobs(valid);
    } catch (e) {
      console.error("Failed to load jobs:", e);
    } finally {
      setLoading(false);
    }
  }, [isConnected, address, getClientJobs, getJob]);

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

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold" style={{ color: "#0a0a0a" }}>Jobs</h1>
          <p className="text-sm mt-0.5" style={{ color: "#a3a3a3" }}>All your escrow jobs</p>
        </div>
        <button
          onClick={loadJobs}
          disabled={loading || !isConnected}
          className="btn-ghost px-3 py-1.5 text-sm disabled:opacity-30 whitespace-nowrap"
        >
          {loading ? "Loading..." : "Refresh"}
        </button>
      </div>

      {!isConnected ? (
        <div className="glass-card p-12 text-center">
          <p className="text-sm" style={{ color: "#a3a3a3" }}>Connect your wallet to view jobs</p>
        </div>
      ) : loading ? (
        <div className="glass-card p-4">
          <div className="space-y-3">
            {[1, 2, 3].map((i) => <div key={i} className="skeleton w-full h-12" />)}
          </div>
        </div>
      ) : jobs.length === 0 ? (
        <div className="glass-card p-12 text-center">
          <p className="text-sm" style={{ color: "#a3a3a3" }}>No jobs found</p>
        </div>
      ) : (
        <div className="glass-card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="table-dark min-w-[640px]">
              <thead>
                <tr>
                  <th>Job ID</th>
                  <th>Agent</th>
                  <th>Amount</th>
                  <th className="hidden sm:table-cell">Fee</th>
                  <th>Status</th>
                  <th className="hidden md:table-cell">Created</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {jobs.map((job) => (
                  <tr key={job.jobId.toString()}>
                    <td className="font-mono text-xs" style={{ color: "#0a0a0a" }}>
                      #{job.jobId.toString()}
                    </td>
                    <td style={{ color: "#0a0a0a" }}>
                      #{job.agentId.toString()}
                    </td>
                    <td className="tabular-nums" style={{ color: "#0a0a0a" }}>
                      ${formatUSDC(job.amount)}
                    </td>
                    <td className="hidden sm:table-cell tabular-nums" style={{ color: "#a3a3a3" }}>
                      ${formatUSDC(job.platformFee)}
                    </td>
                    <td>
                      <StatusBadge status={job.status} />
                    </td>
                    <td className="hidden md:table-cell text-xs" style={{ color: "#a3a3a3" }}>
                      {formatDateTime(job.createdAt)}
                    </td>
                    <td>
                      <JobActions
                        job={job}
                        loading={actionLoading}
                        onAction={handleAction}
                        connectedAddress={address}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function JobActions({
  job,
  loading,
  onAction,
  connectedAddress,
}: {
  job: Job;
  loading: string | null;
  onAction: (action: string, jobId: bigint) => void;
  connectedAddress?: string;
}) {
  const isRouterCreated = connectedAddress && job.client.toLowerCase() !== connectedAddress.toLowerCase();

  if (isRouterCreated && (job.status === 0 || job.status === 1 || job.status === 2 || job.status === 3)) {
    return (
      <span
        className="text-[10px] px-2 py-1 rounded-md"
        style={{
          background: "#fffbeb",
          color: "#92400e",
          border: "1px solid #fde68a",
        }}
      >
        Router job
      </span>
    );
  }

  const buttons: { label: string; action: string; accent?: boolean }[] = [];

  if (job.status === 0) buttons.push({ label: "Cancel", action: "cancel" });
  if (job.status === 3) buttons.push({ label: "Settle", action: "settle", accent: true });
  if (job.status === 1 || job.status === 2 || job.status === 3) {
    buttons.push({ label: "Dispute", action: "dispute" });
  }

  if (buttons.length === 0) return <span style={{ color: "#a3a3a3" }}>—</span>;

  return (
    <div className="flex gap-1.5 flex-wrap">
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
