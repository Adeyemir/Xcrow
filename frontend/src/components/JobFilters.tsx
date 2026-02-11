"use client";

import { JOB_STATUS_LABELS } from "@/lib/utils";

interface JobFiltersProps {
  statusFilter: string;
  onStatusChange: (status: string) => void;
  networkFilter: string;
  onNetworkChange: (network: string) => void;
}

export function JobFilters({
  statusFilter,
  onStatusChange,
  networkFilter,
  onNetworkChange,
}: JobFiltersProps) {
  return (
    <div className="flex items-center gap-2 flex-wrap">
      <select
        value={statusFilter}
        onChange={(e) => onStatusChange(e.target.value)}
      >
        <option value="">All Statuses</option>
        {JOB_STATUS_LABELS.map((label) => (
          <option key={label} value={label}>
            {label}
          </option>
        ))}
      </select>

      <select
        value={networkFilter}
        onChange={(e) => onNetworkChange(e.target.value)}
      >
        <option value="">All Networks</option>
        <option value="local">Same Chain</option>
        <option value="cross">Cross-Chain</option>
      </select>
    </div>
  );
}
