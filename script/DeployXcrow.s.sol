// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {XcrowEscrow} from "../src/core/XcrowEscrow.sol";
import {ReputationPricer} from "../src/core/ReputationPricer.sol";
import {CrossChainSettler} from "../src/core/CrossChainSettler.sol";
import {XcrowRouter} from "../src/core/XcrowRouter.sol";
import {MockIdentityRegistry} from "../test/mocks/MockIdentityRegistry.sol";
import {MockReputationRegistry} from "../test/mocks/MockReputationRegistry.sol";

contract DeployXcrow is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        MockIdentityRegistry idReg = new MockIdentityRegistry();
        MockReputationRegistry repReg = new MockReputationRegistry(address(idReg));

        XcrowEscrow escrow =
            new XcrowEscrow(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, address(idReg), deployer, 250, 3 days);

        ReputationPricer pricer = new ReputationPricer(address(repReg), address(idReg), 20000, 100, 3, "starred");
        pricer.addTrustedReviewer(deployer);

        CrossChainSettler settler = new CrossChainSettler(
            0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA, 0
        );
        settler.configureDomain(6, true, bytes32(0));
        settler.configureDomain(26, true, bytes32(0));
        settler.configureDomain(3, true, bytes32(0));

        XcrowRouter router = new XcrowRouter(
            0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            address(escrow),
            address(pricer),
            address(settler),
            address(idReg),
            address(repReg),
            11155111
        );

        uint256 agentId = idReg.register("ipfs://xcrow-test-agent");
        pricer.setBaseRate(agentId, 5e6);

        vm.stopBroadcast();

        console.log("IdentityRegistry:", address(idReg));
        console.log("ReputationRegistry:", address(repReg));
        console.log("XcrowEscrow:", address(escrow));
        console.log("ReputationPricer:", address(pricer));
        console.log("CrossChainSettler:", address(settler));
        console.log("XcrowRouter:", address(router));
        console.log("Test Agent ID:", agentId);
    }
}
