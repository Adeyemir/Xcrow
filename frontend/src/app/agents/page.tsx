"use client";

import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { useXcrow } from "@/hooks/useXcrow";
import { AgentCard } from "@/components/AgentCard";

interface AgentData {
  agentId: bigint;
  owner: string;
  wallet: string;
  uri: string;
  baseRate: bigint;
  reputationScore: bigint;
  multiplierBps: bigint;
}

const MAX_AGENT_SCAN = 20;

export default function AgentsPage() {
  const { getAgentInfo, getAgentBaseRate, getReputationMultiplier } = useXcrow();
  const [agents, setAgents] = useState<AgentData[]>([]);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState("");
  const router = useRouter();

  const loadAgents = useCallback(async () => {
    setLoading(true);
    const results: AgentData[] = [];
    for (let i = 1; i <= MAX_AGENT_SCAN; i++) {
      try {
        const info = await getAgentInfo(BigInt(i));
        if (!info || info.owner === "0x0000000000000000000000000000000000000000") continue;
        const baseRate = await getAgentBaseRate(BigInt(i));
        const { score, multiplierBps } = await getReputationMultiplier(BigInt(i));
        results.push({
          agentId: BigInt(i),
          owner: info.owner,
          wallet: info.wallet,
          uri: info.uri,
          baseRate,
          reputationScore: score,
          multiplierBps,
        });
      } catch {
        // agent doesn't exist at this ID
      }
    }
    setAgents(results);
    setLoading(false);
  }, [getAgentInfo, getAgentBaseRate, getReputationMultiplier]);

  useEffect(() => {
    loadAgents();
  }, [loadAgents]);

  function handleHire(agentId: bigint) {
    router.push(`/?agent=${agentId.toString()}`);
  }

  const filtered = agents.filter(
    (a) =>
      !search ||
      a.agentId.toString().includes(search) ||
      a.uri.toLowerCase().includes(search.toLowerCase()) ||
      a.owner.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold" style={{ color: "#0a0a0a" }}>
            Agents
          </h1>
          <p className="text-sm mt-0.5" style={{ color: "#a3a3a3" }}>Browse and hire AI agents</p>
        </div>
        <button
          onClick={loadAgents}
          disabled={loading}
          className="btn-ghost px-3 py-1.5 text-sm disabled:opacity-30"
        >
          {loading ? "Loading..." : "Refresh"}
        </button>
      </div>

      <div className="flex gap-3">
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by ID, URI, or owner..."
          className="input-dark flex-1 max-w-sm px-3 py-2.5 text-sm"
        />
      </div>

      {loading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="glass-card p-5">
              <div className="space-y-3">
                <div className="skeleton w-20 h-3" />
                <div className="skeleton w-full h-4" />
                <div className="skeleton w-full h-1.5 rounded-full" />
                <div className="grid grid-cols-2 gap-3">
                  <div className="skeleton w-full h-8" />
                  <div className="skeleton w-full h-8" />
                </div>
                <div className="skeleton w-full h-10 rounded-lg" />
              </div>
            </div>
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <div className="glass-card p-12 text-center">
          <p className="text-sm" style={{ color: "#a3a3a3" }}>No agents found</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {filtered.map((agent) => (
            <AgentCard
              key={agent.agentId.toString()}
              {...agent}
              onHire={handleHire}
            />
          ))}
        </div>
      )}
    </div>
  );
}
