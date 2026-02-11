import { Contract, Signer, Provider } from "ethers";
import XcrowEscrowABI from "./abis/XcrowEscrow.json";
import XcrowRouterABI from "./abis/XcrowRouter.json";
import ReputationPricerABI from "./abis/ReputationPricer.json";
import IdentityRegistryABI from "./abis/IdentityRegistry.json";
import ERC20ABI from "./abis/ERC20.json";

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

export const CCTP_DOMAIN_NAMES: Record<number, string> = {
  0: "Ethereum",
  3: "Arbitrum",
  6: "Base",
  26: "Linea",
};

export function getEscrow(signerOrProvider: Signer | Provider) {
  return new Contract(ADDRESSES.XcrowEscrow, XcrowEscrowABI, signerOrProvider);
}

export function getRouter(signerOrProvider: Signer | Provider) {
  return new Contract(ADDRESSES.XcrowRouter, XcrowRouterABI, signerOrProvider);
}

export function getPricer(signerOrProvider: Signer | Provider) {
  return new Contract(ADDRESSES.ReputationPricer, ReputationPricerABI, signerOrProvider);
}

export function getIdentityRegistry(signerOrProvider: Signer | Provider) {
  return new Contract(ADDRESSES.IdentityRegistry, IdentityRegistryABI, signerOrProvider);
}

export function getUSDC(signerOrProvider: Signer | Provider) {
  return new Contract(ADDRESSES.USDC, ERC20ABI, signerOrProvider);
}
