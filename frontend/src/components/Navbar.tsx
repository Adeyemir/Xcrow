"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { truncateAddress } from "@/lib/utils";

const NAV_LINKS = [
  { href: "/", label: "Dashboard" },
  { href: "/agents", label: "Agents" },
  { href: "/jobs", label: "Jobs" },
  { href: "/settlement", label: "Settlement" },
];

export function Navbar() {
  const pathname = usePathname();

  return (
    <header
      className="sticky top-0 z-50"
      style={{
        background: "rgba(255, 255, 255, 0.85)",
        backdropFilter: "blur(12px)",
        WebkitBackdropFilter: "blur(12px)",
        borderBottom: "1px solid #e5e5e5",
      }}
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-14 sm:h-16 gap-4">
          {/* Logo + Nav */}
          <div className="flex items-center gap-4 sm:gap-8 min-w-0 flex-1">
            <Link href="/" className="flex items-center gap-2 shrink-0">
              <div
                className="w-7 h-7 rounded-lg flex items-center justify-center text-xs font-bold text-white"
                style={{ background: "#0a0a0a" }}
              >
                X
              </div>
              <span className="text-sm sm:text-base font-semibold tracking-tight" style={{ color: "#0a0a0a" }}>
                Xcrow
              </span>
            </Link>
            <nav className="hidden sm:flex items-center gap-1">
              {NAV_LINKS.map((link) => {
                const isActive = pathname === link.href;
                return (
                  <Link
                    key={link.href}
                    href={link.href}
                    className="relative px-3 py-1.5 text-sm rounded-lg transition-all duration-150"
                    style={{
                      color: isActive ? "#0a0a0a" : "#a3a3a3",
                      fontWeight: isActive ? 500 : 400,
                      background: isActive ? "#f5f5f5" : "transparent",
                    }}
                  >
                    {link.label}
                    {isActive && (
                      <span
                        className="absolute bottom-0 left-1/2 -translate-x-1/2 w-4 h-0.5 rounded-full"
                        style={{ background: "#0a0a0a" }}
                      />
                    )}
                  </Link>
                );
              })}
            </nav>
          </div>

          {/* Right: Network + Wallet */}
          <div className="flex items-center gap-2 sm:gap-3">
            <span
              className="hidden sm:inline-flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-lg"
              style={{
                background: "#f5f5f5",
                color: "#737373",
                border: "1px solid #e5e5e5",
              }}
            >
              <span className="w-1.5 h-1.5 rounded-full" style={{ background: "#22c55e" }} />
              Sepolia
            </span>
            <ConnectButton.Custom>
              {({
                account,
                chain,
                openAccountModal,
                openChainModal,
                openConnectModal,
                mounted,
              }) => {
                const ready = mounted;
                const connected = ready && account && chain;

                return (
                  <div
                    {...(!ready && {
                      "aria-hidden": true,
                      style: { opacity: 0, pointerEvents: "none" as const, userSelect: "none" as const },
                    })}
                  >
                    {!connected ? (
                      <button
                        onClick={openConnectModal}
                        className="btn-gradient px-4 py-2 text-sm"
                      >
                        Connect Wallet
                      </button>
                    ) : chain.unsupported ? (
                      <button
                        onClick={openChainModal}
                        className="px-3 py-1.5 text-sm font-medium rounded-lg"
                        style={{
                          background: "#fef2f2",
                          color: "#b91c1c",
                          border: "1px solid #fecaca",
                        }}
                      >
                        Wrong Network
                      </button>
                    ) : (
                      <button
                        onClick={openAccountModal}
                        className="flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg transition-all duration-150"
                        style={{
                          border: "1px solid #e5e5e5",
                          color: "#0a0a0a",
                          background: "#ffffff",
                        }}
                      >
                        <span className="pulse-dot" style={{ background: "#22c55e" }} />
                        <span className="max-w-[90px] sm:max-w-none truncate font-mono text-xs">
                          {truncateAddress(account.address)}
                        </span>
                      </button>
                    )}
                  </div>
                );
              }}
            </ConnectButton.Custom>
          </div>
        </div>

        {/* Mobile Nav */}
        <nav className="sm:hidden flex items-center gap-1 pb-2 overflow-x-auto -mx-1 px-1">
          {NAV_LINKS.map((link) => {
            const isActive = pathname === link.href;
            return (
              <Link
                key={link.href}
                href={link.href}
                className="px-3 py-1.5 text-xs rounded-lg transition-all duration-150 whitespace-nowrap flex-shrink-0"
                style={{
                  color: isActive ? "#0a0a0a" : "#a3a3a3",
                  fontWeight: isActive ? 500 : 400,
                  background: isActive ? "#f5f5f5" : "transparent",
                }}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>
      </div>
    </header>
  );
}
