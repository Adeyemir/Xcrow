import type { Metadata } from "next";
import "./globals.css";
import "@rainbow-me/rainbowkit/styles.css";
import { Providers } from "@/context/providers";
import { Navbar } from "@/components/Navbar";
import { Toaster } from "react-hot-toast";

export const metadata: Metadata = {
  title: "Xcrow Protocol — USDC Payments for the Agent Economy",
  description: "Secure USDC escrow and cross-chain settlement for ERC-8004 AI agents. Hire, pay, and manage autonomous agents with on-chain guarantees.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <Providers>
          <Navbar />
          <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8">
            {children}
          </main>
          <Toaster
            position="bottom-right"
            toastOptions={{
              style: {
                background: '#ffffff',
                color: '#0a0a0a',
                border: '1px solid #e5e5e5',
                borderRadius: '10px',
                fontSize: '13px',
                boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
              },
            }}
          />
        </Providers>
      </body>
    </html>
  );
}
