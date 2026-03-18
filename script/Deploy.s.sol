// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {XcrowEscrow} from "../src/core/XcrowEscrow.sol";
import {ReputationPricer} from "../src/core/ReputationPricer.sol";
import {CrossChainSettler} from "../src/core/CrossChainSettler.sol";
import {XcrowRouter} from "../src/core/XcrowRouter.sol";
import {MockIdentityRegistry} from "../test/mocks/MockIdentityRegistry.sol";
import {MockReputationRegistry} from "../test/mocks/MockReputationRegistry.sol";

/// @title Deploy — Xcrow Protocol (Arc Testnet)
/// @notice Deploys all core contracts + mock registries to Arc Testnet
contract Deploy is Script {
    // Arc Testnet USDC
   address constant USDC = 0x3600000000000000000000000000000000000000;
    // CCTP V2 — Arc addresses (same on all chains)
    address constant CCTP_TOKEN_MESSENGER = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    // CCTP Domain identifiers
    uint32 constant DOMAIN_ETHEREUM = 0;
    uint32 constant DOMAIN_ARBITRUM = 3;
    uint32 constant DOMAIN_BASE = 6;
    uint32 constant DOMAIN_ARC = 26;
    // Local chain ID for Sepolia
   uint32 constant LOCAL_CHAIN_ID = 5042002;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // 1. Deploy mock ERC-8004 registries (replace with real addresses in production)
        MockIdentityRegistry idReg = new MockIdentityRegistry();
        MockReputationRegistry repReg = new MockReputationRegistry(address(idReg));

        // 2. Deploy core contracts
        XcrowEscrow escrow = new XcrowEscrow(
            USDC, address(idReg), deployer, 250, 3 days
        );

        ReputationPricer pricer = new ReputationPricer(
            address(repReg), address(idReg), 20000, 100, 3, "starred"
        );
        pricer.addTrustedReviewer(deployer);

        CrossChainSettler settler = new CrossChainSettler(
            USDC, CCTP_TOKEN_MESSENGER, DOMAIN_ARC       
        );
        settler.configureDomain(DOMAIN_BASE, true, bytes32(0));
        settler.configureDomain(DOMAIN_ARBITRUM, true, bytes32(0));
        settler.configureDomain(DOMAIN_ETHEREUM, true, bytes32(0));

        XcrowRouter router = new XcrowRouter(
            USDC, address(escrow), address(pricer), address(settler),
            address(idReg), address(repReg), LOCAL_CHAIN_ID
        );

        // 3. Post-deploy configuration
        // Authorize the Router to call the CrossChainSettler
        settler.setAuthorizedCaller(address(router), true);

        // 4. Register a test agent
        uint256 agentId = idReg.register("ipfs://xcrow-test-agent");
        pricer.setBaseRate(agentId, 5e6); // 5 USDC base rate

        vm.stopBroadcast();

        console.log("=== Deployed Addresses ===");
        console.log("IdentityRegistry:", address(idReg));
        console.log("ReputationRegistry:", address(repReg));
        console.log("XcrowEscrow:", address(escrow));
        console.log("ReputationPricer:", address(pricer));
        console.log("CrossChainSettler:", address(settler));
        console.log("XcrowRouter:", address(router));
        console.log("Test Agent ID:", agentId);
    }
}
