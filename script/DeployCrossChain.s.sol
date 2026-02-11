// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {CrossChainSettler} from "../src/core/CrossChainSettler.sol";

/// @title DeployCrossChain — Xcrow Protocol (Destination Chain)
/// @notice Deploys the CrossChainSettler to a destination chain (e.g., Base Sepolia)
///         and configures it to accept messages from the source chain.
contract DeployCrossChain is Script {
    // CCTP V2 addresses (same on all CCTP-supported chains)
    address constant CCTP_TOKEN_MESSENGER = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // Read chain-specific config from environment
        address usdc = vm.envAddress("USDC_ADDRESS");
        uint32 localDomain = uint32(vm.envUint("LOCAL_CCTP_DOMAIN"));
        uint32 sourceDomain = uint32(vm.envUint("SOURCE_CCTP_DOMAIN"));
        address sourceRouter = vm.envAddress("SOURCE_ROUTER_ADDRESS");

        console.log("Deployer:", deployer);
        console.log("USDC:", usdc);
        console.log("Local CCTP Domain:", localDomain);
        console.log("Source CCTP Domain:", sourceDomain);

        vm.startBroadcast(pk);

        // Deploy CrossChainSettler on destination chain
        CrossChainSettler settler = new CrossChainSettler(
            usdc, CCTP_TOKEN_MESSENGER, localDomain
        );

        // Configure the source domain so we can also initiate settlements back
        settler.configureDomain(sourceDomain, true, bytes32(0));

        // Authorize the source chain's router (if known)
        if (sourceRouter != address(0)) {
            settler.setAuthorizedCaller(sourceRouter, true);
        }

        vm.stopBroadcast();

        console.log("=== Destination Chain Deployment ===");
        console.log("CrossChainSettler:", address(settler));
        console.log("Authorized source router:", sourceRouter);
    }
}
