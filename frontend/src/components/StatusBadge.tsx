import { getStatusLabel } from "@/lib/utils";

const BADGE_CLASSES: Record<string, string> = {
  Created: "badge-created",
  Accepted: "badge-accepted",
  InProgress: "badge-inprogress",
  Completed: "badge-completed",
  Settled: "badge-settled",
  Disputed: "badge-disputed",
  Cancelled: "badge-cancelled",
  Refunded: "badge-refunded",
  Expired: "badge-expired",
};

const DOT_COLORS: Record<string, string> = {
  Created: "#737373",
  Accepted: "#3b82f6",
  InProgress: "#eab308",
  Completed: "#22c55e",
  Settled: "#ffffff",
  Disputed: "#ef4444",
  Cancelled: "#a3a3a3",
  Refunded: "#f59e0b",
  Expired: "#d4d4d4",
};

export function StatusBadge({ status }: { status: number }) {
  const label = getStatusLabel(status);
  const badgeClass = BADGE_CLASSES[label] ?? "badge-cancelled";
  const dotColor = DOT_COLORS[label] ?? "#a3a3a3";

  return (
    <span className={`badge ${badgeClass}`}>
      <span className="pulse-dot" style={{ background: dotColor }} />
      {label}
    </span>
  );
}
