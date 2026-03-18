import { Contract, Signer, Provider } from "ethers";
import XcrowEscrowABI from "./abis/XcrowEscrow.json";
import XcrowRouterABI from "./abis/XcrowRouter.json";
import ReputationPricerABI from "./abis/ReputationPricer.json";
import IdentityRegistryABI from "./abis/IdentityRegistry.json";
import ERC20ABI from "./abis/ERC20.json";

export const ADDRESSES = {
  USDC: "0x3600000000000000000000000000000000000000",
  IdentityRegistry: "0x54f6964C210A834357559a781B9208f3AFd7cd1B",
  ReputationRegistry: "0xbE613274985346A1dFD7355871675Bf1dAAfec0E",
  XcrowEscrow: "0x57e902A674b57971ec94aD1E3e203DF1B2479BC0",
  ReputationPricer: "0x4698BCCD1E64317C3d40eac6C05303D6784EDF14",
  CrossChainSettler: "0x940c62B902CB31001eC4CeA7Bf04253dAa983e17",
  XcrowRouter: "0x27aa8D66de7ACEdf4996E91BF0CcF79E3eAc2829",
} as const;

export const ARC_CHAIN_ID = 5042002;

export const CCTP_DOMAIN_NAMES: Record<number, string> = {
  0: "Ethereum",
  3: "Arbitrum",
  6: "Base",
  26: "Arc",
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