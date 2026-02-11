"use client";

import { truncateAddress, formatUSDC } from "@/lib/utils";

interface AgentCardProps {
  agentId: bigint;
  uri: string;
  owner: string;
  wallet: string;
  baseRate: bigint;
  reputationScore: bigint;
  multiplierBps: bigint;
  onHire: (agentId: bigint) => void;
}

export function AgentCard({
  agentId,
  uri,
  owner,
  wallet,
  baseRate,
  reputationScore,
  multiplierBps,
  onHire,
}: AgentCardProps) {
  const multiplier = Number(multiplierBps) / 10000;
  const effectiveRate = (baseRate * multiplierBps) / 10000n;
  const repScore = Number(reputationScore);
  const repPercent = Math.min(100, Math.max(0, (repScore / 100) * 100));

  return (
    <div className="glass-card p-5 flex flex-col gap-4 group">
      <div className="flex items-start justify-between">
        <div className="min-w-0">
          <div className="text-[10px] font-medium uppercase tracking-wider mb-1" style={{ color: "#a3a3a3" }}>
            Agent #{agentId.toString()}
          </div>
          <div className="text-sm font-medium truncate max-w-[200px]" style={{ color: "#0a0a0a" }}>
            {uri || "No URI set"}
          </div>
        </div>
        <span
          className="text-[10px] px-2 py-0.5 rounded-md shrink-0"
          style={{
            background: "#f5f5f5",
            color: "#737373",
            border: "1px solid #e5e5e5",
          }}
        >
          Sepolia
        </span>
      </div>

      {/* Reputation bar */}
      <div>
        <div className="flex items-center justify-between text-[10px] mb-1.5">
          <span style={{ color: "#a3a3a3" }}>Reputation</span>
          <span style={{ color: "#525252" }}>{repScore} pts · {multiplier.toFixed(2)}x</span>
        </div>
        <div className="w-full h-1.5 rounded-full overflow-hidden" style={{ background: "#f0f0f0" }}>
          <div
            className="h-full rounded-full transition-all duration-500"
            style={{
              width: `${repPercent}%`,
              background: "#0a0a0a",
            }}
          />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 text-xs">
        <div>
          <div className="text-[10px] uppercase tracking-wider mb-0.5" style={{ color: "#a3a3a3" }}>Owner</div>
          <div className="font-mono" style={{ color: "#525252" }}>{truncateAddress(owner)}</div>
        </div>
        <div>
          <div className="text-[10px] uppercase tracking-wider mb-0.5" style={{ color: "#a3a3a3" }}>Wallet</div>
          <div className="font-mono" style={{ color: "#525252" }}>{wallet ? truncateAddress(wallet) : "—"}</div>
        </div>
        <div>
          <div className="text-[10px] uppercase tracking-wider mb-0.5" style={{ color: "#a3a3a3" }}>Base Rate</div>
          <div style={{ color: "#525252" }}>${formatUSDC(baseRate)}</div>
        </div>
        <div>
          <div className="text-[10px] uppercase tracking-wider mb-0.5" style={{ color: "#a3a3a3" }}>Effective</div>
          <div className="font-bold" style={{ color: "#0a0a0a" }}>${formatUSDC(effectiveRate)}</div>
        </div>
      </div>

      <button
        onClick={() => onHire(agentId)}
        className="btn-gradient w-full py-2.5 text-sm font-medium mt-auto"
      >
        Hire Agent
      </button>
    </div>
  );
}
