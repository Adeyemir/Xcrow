import { ethers } from "ethers";
import dotenv from "dotenv";
import { fileURLToPath } from "url";
import { dirname, resolve } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load .env from project root first, then mcp/.env
dotenv.config({ path: resolve(__dirname, "../../.env") });
dotenv.config({ path: resolve(__dirname, "../.env") });

// --- Contract addresses (Sepolia) ---
export const ADDRESSES = {
    USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
    IdentityRegistry: "0xeD89c1407871f215e1EcE3A3c6CC3a708d5C93A5",
    ReputationRegistry: "0x55BF88727b2C175CF09A263806AE3C7AD81e7860",
    XcrowEscrow: "0x2Cd88Fa68B44d99dD7853A45e810Ee3f117C0445",
    ReputationPricer: "0x16Cb8F60f3145a8Adb640Cf86cA4Ad687E8b1E15",
    CrossChainSettler: "0x32Af375d550a8F23ce061680182a614D52695155",
    XcrowRouter: "0x726f13Fac1F381CE8b675de93AaaED5Ab37DB9BA",
} as const;

export const SEPOLIA_CHAIN_ID = 11155111;

export const CCTP_DOMAINS: Record<number, string> = {
    0: "Ethereum",
    3: "Arbitrum",
    6: "Base",
    26: "Arc",
};

export const JOB_STATUS_LABELS: Record<number, string> = {
    0: "Created",
    1: "Accepted",
    2: "InProgress",
    3: "Completed",
    4: "Settled",
    5: "Disputed",
    6: "Cancelled",
    7: "Expired",
};

// --- Provider & Wallet ---
const rpcUrl = process.env.ARC_RPC_URL || "https://rpc.testnet.arc.network";
const privateKey = process.env.PRIVATE_KEY;

if (!privateKey) {
    throw new Error("PRIVATE_KEY environment variable is required. Set it in .env or mcp/.env");
}

export const provider = new ethers.JsonRpcProvider(rpcUrl);
export const wallet = new ethers.Wallet(privateKey, provider);
