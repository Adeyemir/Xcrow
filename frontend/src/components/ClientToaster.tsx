"use client";

import { Toaster } from "react-hot-toast";

export function ClientToaster() {
  return (
    <Toaster
      position="bottom-right"
      toastOptions={{
        style: {
          borderRadius: "8px",
          border: "1px solid #e5e5e5",
          boxShadow: "0 4px 12px rgba(0,0,0,0.08)",
          fontSize: "13px",
        },
      }}
    />
  );
}
