"use client";

import { useState } from "react";
import { StatusBadge } from "./StatusBadge";
import { Pagination } from "./Pagination";
import { JobFilters } from "./JobFilters";
import { Job } from "@/hooks/useXcrow";
import { formatUSDC, formatDateTime, JOB_STATUS_LABELS } from "@/lib/utils";
import { CCTP_DOMAIN_NAMES } from "@/lib/contracts";

const PAGE_SIZE = 10;

interface JobsTableProps {
  jobs: Job[];
  onAction?: (action: string, jobId: bigint) => void;
  showActions?: boolean;
}

export function JobsTable({ jobs, onAction, showActions = false }: JobsTableProps) {
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState("");
  const [networkFilter, setNetworkFilter] = useState("");

  const filtered = jobs.filter((job) => {
    if (statusFilter && JOB_STATUS_LABELS[job.status] !== statusFilter) return false;
    if (networkFilter === "local" && job.isCrossChain) return false;
    if (networkFilter === "cross" && !job.isCrossChain) return false;
    return true;
  });

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  return (
    <div className="glass-card overflow-hidden">
      <div
        className="flex items-center justify-between px-4 py-3"
        style={{ borderBottom: "1px solid #e5e5e5" }}
      >
        <h3 className="text-sm font-medium" style={{ color: "#0a0a0a" }}>Jobs</h3>
        <JobFilters
          statusFilter={statusFilter}
          onStatusChange={(s) => { setStatusFilter(s); setPage(1); }}
          networkFilter={networkFilter}
          onNetworkChange={(n) => { setNetworkFilter(n); setPage(1); }}
        />
      </div>

      <div className="overflow-x-auto">
        <table className="table-dark min-w-[640px]">
          <thead>
            <tr>
              <th>Date</th>
              <th>Agent</th>
              <th>Amount</th>
              <th>Fee</th>
              <th>Status</th>
              <th>Chain</th>
              {showActions && <th>Actions</th>}
            </tr>
          </thead>
          <tbody>
            {paged.length === 0 ? (
              <tr>
                <td colSpan={showActions ? 7 : 6} className="px-4 py-8 text-center" style={{ color: "#a3a3a3" }}>
                  No jobs found
                </td>
              </tr>
            ) : (
              paged.map((job) => (
                <tr key={job.jobId.toString()}>
                  <td style={{ color: "#525252" }}>{formatDateTime(job.createdAt)}</td>
                  <td style={{ color: "#0a0a0a" }}>#{job.agentId.toString()}</td>
                  <td className="tabular-nums" style={{ color: "#0a0a0a" }}>${formatUSDC(job.amount)}</td>
                  <td className="tabular-nums" style={{ color: "#a3a3a3" }}>${formatUSDC(job.platformFee)}</td>
                  <td><StatusBadge status={job.status} /></td>
                  <td style={{ color: "#737373" }}>
                    {job.isCrossChain
                      ? `Sepolia → ${CCTP_DOMAIN_NAMES[job.destinationDomain] ?? `Domain ${job.destinationDomain}`}`
                      : "Sepolia"}
                  </td>
                  {showActions && (
                    <td><JobActions job={job} onAction={onAction} /></td>
                  )}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
    </div>
  );
}

function JobActions({
  job,
  onAction,
}: {
  job: Job;
  onAction?: (action: string, jobId: bigint) => void;
}) {
  const status = job.status;
  const buttons: { label: string; action: string; accent?: boolean }[] = [];

  if (status === 0) buttons.push({ label: "Cancel", action: "cancel" });
  if (status === 3) buttons.push({ label: "Settle", action: "settle", accent: true });
  if (status === 1 || status === 2 || status === 3) buttons.push({ label: "Dispute", action: "dispute" });

  if (buttons.length === 0) return <span style={{ color: "#a3a3a3" }}>—</span>;

  return (
    <div className="flex gap-1.5">
      {buttons.map((btn) => (
        <button
          key={btn.action}
          onClick={() => onAction?.(btn.action, job.jobId)}
          className={btn.accent ? "btn-gradient px-2.5 py-1 text-xs" : "btn-ghost px-2.5 py-1 text-xs"}
        >
          {btn.label}
        </button>
      ))}
    </div>
  );
}
