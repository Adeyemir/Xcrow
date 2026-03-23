// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {XcrowEscrow} from "../src/core/XcrowEscrow.sol";
import {ReputationPricer} from "../src/core/ReputationPricer.sol";
import {CrossChainSettler} from "../src/core/CrossChainSettler.sol";
import {XcrowRouter} from "../src/core/XcrowRouter.sol";

/// @title Deploy — Xcrow Protocol (Arc Testnet)
/// @notice Deploys all core contracts against real ERC-8004 registries on Arc Testnet
contract Deploy is Script {
    // Arc Testnet USDC
    address constant USDC = 0x3600000000000000000000000000000000000000;
    // CCTP V2 — Arc addresses
    address constant CCTP_TOKEN_MESSENGER = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    // CCTP Domain identifiers
    uint32 constant DOMAIN_ETHEREUM = 0;
    uint32 constant DOMAIN_ARBITRUM = 3;
    uint32 constant DOMAIN_BASE = 6;
    uint32 constant DOMAIN_ARC = 26;
    // Arc Testnet chain ID
    uint32 constant LOCAL_CHAIN_ID = 5042002;
    // Real ERC-8004 contracts on Arc Testnet
    address constant ERC8004_IDENTITY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address constant ERC8004_REPUTATION = 0x8004B663056A597Dffe9eCcC1965A193B7388713;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // 1. Deploy core contracts against real ERC-8004 registries
        XcrowEscrow escrow = new XcrowEscrow(USDC, ERC8004_IDENTITY, deployer, 250, 3 days, 30 minutes);

        ReputationPricer pricer = new ReputationPricer(ERC8004_REPUTATION, ERC8004_IDENTITY, 20000, 100, 3, "starred");
        pricer.addTrustedReviewer(deployer);

        CrossChainSettler settler = new CrossChainSettler(USDC, CCTP_TOKEN_MESSENGER, DOMAIN_ARC);
        settler.configureDomain(DOMAIN_BASE, true, bytes32(0));
        settler.configureDomain(DOMAIN_ARBITRUM, true, bytes32(0));
        settler.configureDomain(DOMAIN_ETHEREUM, true, bytes32(0));

        XcrowRouter router = new XcrowRouter(
            USDC,
            address(escrow),
            address(pricer),
            address(settler),
            ERC8004_IDENTITY,
            ERC8004_REPUTATION,
            LOCAL_CHAIN_ID
        );

        // 2. Authorize the Router to call the CrossChainSettler
        settler.setAuthorizedCaller(address(router), true);

        vm.stopBroadcast();

        console.log("=== Deployed Addresses ===");
        console.log("IdentityRegistry (ERC-8004):", ERC8004_IDENTITY);
        console.log("ReputationRegistry (ERC-8004):", ERC8004_REPUTATION);
        console.log("XcrowEscrow:", address(escrow));
        console.log("ReputationPricer:", address(pricer));
        console.log("CrossChainSettler:", address(settler));
        console.log("XcrowRouter:", address(router));
    }
}
