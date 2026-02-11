"use client";

import { useState, useEffect } from "react";
import { useAccount } from "wagmi";
import toast from "react-hot-toast";
import { useXcrow, makeTaskHash } from "@/hooks/useXcrow";
import { formatUSDC, parseUSDC } from "@/lib/utils";

const QUICK_AMOUNTS = [5, 10, 25, 50];
const PROTOCOL_FEE_BPS = 250; // 2.5%

export function HireAgentCard() {
  const { isConnected } = useAccount();
  const { hireAgent } = useXcrow();
  const [agentId, setAgentId] = useState("");
  const [amount, setAmount] = useState("");
  const [loading, setLoading] = useState(false);

  const amountBigInt = amount ? parseUSDC(amount) : 0n;
  const fee = (amountBigInt * BigInt(PROTOCOL_FEE_BPS)) / 10000n;
  const total = amountBigInt + fee;

  useEffect(() => {
    toast.dismiss();
  }, []);

  async function handleHire() {
    if (!agentId || !amount) return;
    setLoading(true);
    try {
      const taskHash = makeTaskHash(`job-${Date.now()}`);
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 3600);
      await hireAgent(BigInt(agentId), amountBigInt, taskHash, deadline);
      setAmount("");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="glass-card p-5 sm:p-6">
      <h2 className="text-xs font-medium uppercase tracking-wider mb-4" style={{ color: "#a3a3a3" }}>
        Hire Agent
      </h2>

      <div className="space-y-4">
        <div>
          <label className="block text-xs mb-1.5" style={{ color: "#737373" }}>Agent ID</label>
          <input
            type="number"
            min="1"
            value={agentId}
            onChange={(e) => setAgentId(e.target.value)}
            placeholder="Enter agent ID"
            className="input-dark w-full px-3 py-2.5 text-sm"
          />
        </div>

        <div>
          <label className="block text-xs mb-1.5" style={{ color: "#737373" }}>Amount (USDC)</label>
          <input
            type="number"
            min="0"
            step="0.01"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            className="input-dark w-full px-3 py-2.5 text-sm"
          />
          <div className="flex gap-2 mt-2.5">
            {QUICK_AMOUNTS.map((v) => (
              <button
                key={v}
                onClick={() => setAmount(v.toString())}
                className="btn-ghost flex-1 py-1.5 text-xs"
              >
                ${v}
              </button>
            ))}
          </div>
        </div>

        {amountBigInt > 0n && (
          <div
            className="rounded-lg p-3.5 text-xs space-y-2"
            style={{ background: "#fafafa", border: "1px solid #e5e5e5" }}
          >
            <div className="flex justify-between" style={{ color: "#525252" }}>
              <span>Amount</span>
              <span className="tabular-nums">${formatUSDC(amountBigInt)}</span>
            </div>
            <div className="flex justify-between" style={{ color: "#525252" }}>
              <span>Protocol fee (2.5%)</span>
              <span className="tabular-nums">${formatUSDC(fee)}</span>
            </div>
            <div
              className="flex justify-between font-medium pt-2"
              style={{
                color: "#0a0a0a",
                borderTop: "1px solid #e5e5e5",
              }}
            >
              <span>Total</span>
              <span className="tabular-nums font-bold">${formatUSDC(total)} USDC</span>
            </div>
          </div>
        )}

        <button
          onClick={handleHire}
          disabled={!isConnected || !agentId || !amount || loading}
          className="btn-gradient w-full py-3 text-sm font-medium"
        >
          {loading ? (
            <span className="flex items-center justify-center gap-2">
              <svg className="animate-spin w-4 h-4" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" fill="none" strokeDasharray="31.4 31.4" /></svg>
              Processing...
            </span>
          ) : (
            "Hire with USDC"
          )}
        </button>

        <p className="text-center text-[10px]" style={{ color: "#a3a3a3" }}>
          Powered by Circle · CCTP V2
        </p>
      </div>
    </div>
  );
}
