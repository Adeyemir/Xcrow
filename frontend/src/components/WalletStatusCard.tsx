"use client";

import { useAccount, useReadContract } from "wagmi";
import { truncateAddress, formatUSDC, explorerAddressLink } from "@/lib/utils";
import { ADDRESSES } from "@/lib/contracts";
import ERC20ABI from "@/lib/abis/ERC20.json";
import { ConnectButton } from "@rainbow-me/rainbowkit";

export function WalletStatusCard() {
  const { address, isConnected, chain } = useAccount();

  const { data: balance } = useReadContract({
    address: ADDRESSES.USDC as `0x${string}`,
    abi: ERC20ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  return (
    <div className="glass-card p-5 sm:p-6">
      <h2 className="text-xs font-medium uppercase tracking-wider mb-4" style={{ color: "#a3a3a3" }}>
        Wallet Status
      </h2>

      {!isConnected ? (
        <div className="text-center py-6">
          <div
            className="w-12 h-12 mx-auto mb-3 rounded-xl flex items-center justify-center"
            style={{ background: "#f5f5f5", border: "1px solid #e5e5e5" }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" style={{ color: "#a3a3a3" }}>
              <path d="M21 12V7H5a2 2 0 0 1 0-4h14v4" />
              <path d="M3 5v14a2 2 0 0 0 2 2h16v-5" />
              <path d="M18 12a2 2 0 0 0 0 4h4v-4Z" />
            </svg>
          </div>
          <p className="text-sm mb-3" style={{ color: "#a3a3a3" }}>No wallet connected</p>
          <ConnectButton.Custom>
            {({ openConnectModal, mounted }) => (
              <button
                onClick={openConnectModal}
                disabled={!mounted}
                className="btn-gradient px-5 py-2 text-sm"
              >
                Connect Wallet
              </button>
            )}
          </ConnectButton.Custom>
        </div>
      ) : (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs" style={{ color: "#a3a3a3" }}>Status</span>
            <span className="flex items-center gap-1.5 text-sm font-medium" style={{ color: "#22c55e" }}>
              <span className="pulse-dot" style={{ background: "#22c55e" }} />
              Connected
            </span>
          </div>

          <div className="flex items-center justify-between">
            <span className="text-xs" style={{ color: "#a3a3a3" }}>Address</span>
            <a
              href={explorerAddressLink(address!)}
              target="_blank"
              rel="noreferrer"
              className="text-sm font-mono hover:underline max-w-[140px] truncate"
              style={{ color: "#0a0a0a" }}
            >
              {truncateAddress(address!)}
            </a>
          </div>

          <div className="flex items-center justify-between">
            <span className="text-xs" style={{ color: "#a3a3a3" }}>Network</span>
            <span className="text-sm" style={{ color: "#0a0a0a" }}>
              {chain?.name ?? "Unknown"}
            </span>
          </div>

          <div
            className="mt-1 pt-3 flex items-center justify-between"
            style={{ borderTop: "1px solid #f0f0f0" }}
          >
            <span className="text-xs" style={{ color: "#a3a3a3" }}>USDC Balance</span>
            <span className="text-lg font-semibold tabular-nums" style={{ color: "#0a0a0a" }}>
              {balance === undefined ? (
                <span className="skeleton inline-block w-16 h-5" />
              ) : (
                `$${formatUSDC(balance as bigint)}`
              )}
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
