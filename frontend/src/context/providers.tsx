"use client";

import { ReactNode, useState } from "react";
import dynamic from "next/dynamic";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig, http } from "wagmi";
import {
  connectorsForWallets,
  lightTheme,
} from "@rainbow-me/rainbowkit";
import {
  injectedWallet,
  metaMaskWallet,
  rabbyWallet,
  coinbaseWallet,
  braveWallet,
} from "@rainbow-me/rainbowkit/wallets";
import { sepolia } from "wagmi/chains";

// Dynamic import to avoid localStorage SSR error during next build
const RainbowKitProvider = dynamic(
  () => import("@rainbow-me/rainbowkit").then((mod) => mod.RainbowKitProvider),
  { ssr: false }
);

const connectors = connectorsForWallets(
  [
    {
      groupName: "Browser Wallets",
      wallets: [metaMaskWallet, rabbyWallet, coinbaseWallet, braveWallet, injectedWallet],
    },
  ],
  { appName: "Xcrow Protocol", projectId: "placeholder" }
);

const config = createConfig({
  connectors,
  chains: [sepolia],
  transports: {
    [sepolia.id]: http("https://ethereum-sepolia-rpc.publicnode.com"),
  },
});

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <QueryClientProvider client={queryClient}>
      <WagmiProvider config={config}>
        <RainbowKitProvider
          theme={lightTheme({
            accentColor: '#0a0a0a',
            accentColorForeground: 'white',
            borderRadius: 'medium',
          })}
        >
          {children}
        </RainbowKitProvider>
      </WagmiProvider>
    </QueryClientProvider>
  );
}
