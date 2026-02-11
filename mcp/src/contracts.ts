import { ethers } from "ethers";
import { wallet, ADDRESSES } from "./config.js";
import { createRequire } from "module";

const require = createRequire(import.meta.url);

// Load ABIs
const XcrowEscrowABI = require("./abis/XcrowEscrow.json");
const XcrowRouterABI = require("./abis/XcrowRouter.json");
const ERC20ABI = require("./abis/ERC20.json");
const ReputationPricerABI = require("./abis/ReputationPricer.json");
const IdentityRegistryABI = require("./abis/IdentityRegistry.json");

// Contract instances (connected to wallet for signing)
export const escrow = new ethers.Contract(ADDRESSES.XcrowEscrow, XcrowEscrowABI, wallet);
export const router = new ethers.Contract(ADDRESSES.XcrowRouter, XcrowRouterABI, wallet);
export const usdc = new ethers.Contract(ADDRESSES.USDC, ERC20ABI, wallet);
export const pricer = new ethers.Contract(ADDRESSES.ReputationPricer, ReputationPricerABI, wallet);
export const identityRegistry = new ethers.Contract(ADDRESSES.IdentityRegistry, IdentityRegistryABI, wallet);

// Read-only provider instance for view calls
export const escrowRead = new ethers.Contract(ADDRESSES.XcrowEscrow, XcrowEscrowABI, wallet.provider);
export const routerRead = new ethers.Contract(ADDRESSES.XcrowRouter, XcrowRouterABI, wallet.provider);
