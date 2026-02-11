export function formatUSDC(amount: bigint): string {
  const n = Number(amount) / 1_000_000;
  return n.toFixed(2);
}

export function parseUSDC(amount: string): bigint {
  const n = Math.round(parseFloat(amount) * 1_000_000);
  return BigInt(n);
}

export function truncateAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function explorerTxLink(hash: string): string {
  return `https://sepolia.etherscan.io/tx/${hash}`;
}

export function explorerAddressLink(address: string): string {
  return `https://sepolia.etherscan.io/address/${address}`;
}

export const JOB_STATUS_LABELS = [
  "Created",
  "Accepted",
  "InProgress",
  "Completed",
  "Settled",
  "Disputed",
  "Cancelled",
  "Refunded",
  "Expired",
] as const;

export type JobStatusLabel = (typeof JOB_STATUS_LABELS)[number];

export function getStatusLabel(status: number): JobStatusLabel {
  return JOB_STATUS_LABELS[status] ?? "Unknown";
}

export const STATUS_BADGE_CLASSES: Record<string, string> = {
  Created: "bg-yellow-100 text-yellow-800",
  Accepted: "bg-blue-100 text-blue-800",
  InProgress: "bg-purple-100 text-purple-800",
  Completed: "bg-green-100 text-green-800",
  Settled: "bg-emerald-100 text-emerald-800",
  Disputed: "bg-red-100 text-red-800",
  Cancelled: "bg-gray-100 text-gray-600",
  Refunded: "bg-orange-100 text-orange-800",
  Expired: "bg-gray-100 text-gray-600",
};

export function formatDate(timestamp: bigint): string {
  if (timestamp === 0n) return "—";
  return new Date(Number(timestamp) * 1000).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function formatDateTime(timestamp: bigint): string {
  if (timestamp === 0n) return "—";
  return new Date(Number(timestamp) * 1000).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
