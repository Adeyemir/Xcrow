// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CrossChainSettler} from "../src/core/CrossChainSettler.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockTokenMessenger} from "./mocks/MockCCTP.sol";

contract CrossChainSettlerTest is Test {
    CrossChainSettler public settler;
    MockUSDC public usdc;
    MockTokenMessenger public messenger;

    address public owner = address(this);
    address public router = makeAddr("router");
    address public agentWallet = makeAddr("agentWallet");

    uint32 public constant LOCAL_DOMAIN = 0; // Sepolia
    uint32 public constant BASE_DOMAIN = 6;
    uint32 public constant ARC_DOMAIN = 26;
    uint32 public constant UNSUPPORTED_DOMAIN = 999;

    uint256 public constant SETTLE_AMOUNT = 100e6; // 100 USDC

    event CrossChainSettlementInitiated(uint256 indexed jobId, uint32 indexed destinationDomain, bytes32 mintRecipient, uint256 amount, uint64 cctpNonce);

    function setUp() public {
        usdc = new MockUSDC();
        messenger = new MockTokenMessenger();

        settler = new CrossChainSettler(
            address(usdc),
            address(messenger),
            LOCAL_DOMAIN
        );

        // Configure supported domains
        settler.configureDomain(BASE_DOMAIN, true, bytes32(0));
        settler.configureDomain(ARC_DOMAIN, true, bytes32(0));

        // Authorize this test contract as a caller
        settler.setAuthorizedCaller(address(this), true);

        // Fund settler with USDC (simulates escrow transfer)
        usdc.mint(address(settler), 10_000e6);
    }

    // =========================================
    // settleCrossChain tests
    // =========================================

    function test_settleCrossChain_success() public {
        bytes32 recipient = settler.addressToBytes32(agentWallet);

        uint64 nonce = settler.settleCrossChain(
            1, // jobId
            SETTLE_AMOUNT,
            BASE_DOMAIN,
            recipient,
            "" // no hook data
        );

        assertEq(nonce, 0); // First nonce

        // Verify settlement record
        CrossChainSettler.Settlement memory s = settler.getSettlement(1);
        assertEq(s.jobId, 1);
        assertEq(s.amount, SETTLE_AMOUNT);
        assertEq(s.destinationDomain, BASE_DOMAIN);
        assertEq(s.mintRecipient, recipient);
        assertTrue(s.completed);
        assertGt(s.settledAt, 0);

        // Verify CCTP was called
        assertEq(messenger.getBurnCount(), 1);
    }

    function test_settleCrossChain_toArc() public {
        bytes32 recipient = settler.addressToBytes32(agentWallet);

        uint64 nonce = settler.settleCrossChain(
            2, // jobId
            50e6, // 50 USDC
            ARC_DOMAIN,
            recipient,
            ""
        );

        CrossChainSettler.Settlement memory s = settler.getSettlement(2);
        assertEq(s.destinationDomain, ARC_DOMAIN);
        assertEq(s.amount, 50e6);
    }

    function test_settleCrossChain_withHookData() public {
        bytes32 recipient = settler.addressToBytes32(agentWallet);
        bytes memory hookData = abi.encode("auto-stake");

        settler.settleCrossChain(3, SETTLE_AMOUNT, BASE_DOMAIN, recipient, hookData);

        MockTokenMessenger.BurnRecord memory burn = messenger.getLastBurn();
        assertEq(burn.hookData, hookData);
    }

    function test_settleCrossChain_emitsEvent() public {
        bytes32 recipient = settler.addressToBytes32(agentWallet);

        vm.expectEmit(true, true, false, true);
        emit CrossChainSettlementInitiated(
            1, BASE_DOMAIN, recipient, SETTLE_AMOUNT, 0
        );

        settler.settleCrossChain(1, SETTLE_AMOUNT, BASE_DOMAIN, recipient, "");
    }

    function test_settleCrossChain_revert_unsupportedDomain() public {
        bytes32 recipient = settler.addressToBytes32(agentWallet);

        vm.expectRevert("Unsupported destination");
        settler.settleCrossChain(1, SETTLE_AMOUNT, UNSUPPORTED_DOMAIN, recipient, "");
    }

    function test_settleCrossChain_revert_zeroAmount() public {
        bytes32 recipient = settler.addressToBytes32(agentWallet);

        vm.expectRevert("Amount must be > 0");
        settler.settleCrossChain(1, 0, BASE_DOMAIN, recipient, "");
    }

    function test_settleCrossChain_revert_zeroRecipient() public {
        vm.expectRevert("Invalid recipient");
        settler.settleCrossChain(1, SETTLE_AMOUNT, BASE_DOMAIN, bytes32(0), "");
    }

    function test_settleCrossChain_revert_doubleSettle() public {
        bytes32 recipient = settler.addressToBytes32(agentWallet);

        settler.settleCrossChain(1, SETTLE_AMOUNT, BASE_DOMAIN, recipient, "");

        vm.expectRevert("Already settled");
        settler.settleCrossChain(1, SETTLE_AMOUNT, BASE_DOMAIN, recipient, "");
    }

    function test_settleCrossChain_multipleJobs() public {
        bytes32 recipient = settler.addressToBytes32(agentWallet);

        settler.settleCrossChain(1, 100e6, BASE_DOMAIN, recipient, "");
        settler.settleCrossChain(2, 200e6, ARC_DOMAIN, recipient, "");
        settler.settleCrossChain(3, 50e6, BASE_DOMAIN, recipient, "");

        assertEq(settler.getSettlementCount(), 3);
        assertEq(messenger.getBurnCount(), 3);
    }

    // =========================================
    // Domain configuration tests
    // =========================================

    function test_configureDomain() public {
        settler.configureDomain(99, true, bytes32(uint256(1)));
        assertTrue(settler.supportedDomains(99));
    }

    function test_configureDomains_batch() public {
        uint32[] memory domains = new uint32[](2);
        bool[] memory supported = new bool[](2);
        bytes32[] memory settlers = new bytes32[](2);

        domains[0] = 10;
        domains[1] = 11;
        supported[0] = true;
        supported[1] = true;
        settlers[0] = bytes32(0);
        settlers[1] = bytes32(0);

        settler.configureDomains(domains, supported, settlers);

        assertTrue(settler.supportedDomains(10));
        assertTrue(settler.supportedDomains(11));
    }

    function test_configureDomains_revert_mismatch() public {
        uint32[] memory domains = new uint32[](2);
        bool[] memory supported = new bool[](1); // mismatch
        bytes32[] memory settlers = new bytes32[](2);

        domains[0] = 10;
        domains[1] = 11;
        supported[0] = true;
        settlers[0] = bytes32(0);
        settlers[1] = bytes32(0);

        vm.expectRevert("Length mismatch");
        settler.configureDomains(domains, supported, settlers);
    }

    function test_disableDomain() public {
        settler.configureDomain(BASE_DOMAIN, false, bytes32(0));
        assertFalse(settler.supportedDomains(BASE_DOMAIN));

        bytes32 recipient = settler.addressToBytes32(agentWallet);
        vm.expectRevert("Unsupported destination");
        settler.settleCrossChain(1, SETTLE_AMOUNT, BASE_DOMAIN, recipient, "");
    }

    // =========================================
    // Utility tests
    // =========================================

    function test_addressToBytes32_roundtrip() public view {
        bytes32 encoded = settler.addressToBytes32(agentWallet);
        address decoded = settler.bytes32ToAddress(encoded);
        assertEq(decoded, agentWallet);
    }

    function test_getSettlementFee() public view {
        uint256 fee = settler.getSettlementFee(SETTLE_AMOUNT, BASE_DOMAIN);
        assertEq(fee, messenger.MOCK_MIN_FEE());
    }

    // =========================================
    // Admin tests
    // =========================================

    function test_rescueTokens() public {
        MockUSDC otherToken = new MockUSDC();
        otherToken.mint(address(settler), 1000e6);

        settler.rescueTokens(address(otherToken), 1000e6);
        assertEq(otherToken.balanceOf(owner), 1000e6);
    }

    function test_pause_blocksSettlement() public {
        settler.pause();

        bytes32 recipient = settler.addressToBytes32(agentWallet);
        vm.expectRevert();
        settler.settleCrossChain(1, SETTLE_AMOUNT, BASE_DOMAIN, recipient, "");
    }

    function test_unpause_resumesSettlement() public {
        settler.pause();
        settler.unpause();

        bytes32 recipient = settler.addressToBytes32(agentWallet);
        settler.settleCrossChain(1, SETTLE_AMOUNT, BASE_DOMAIN, recipient, "");
        assertEq(settler.getSettlementCount(), 1);
    }

    function test_onlyOwner_configureDomain() public {
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert();
        settler.configureDomain(99, true, bytes32(0));
    }

    function test_settleCrossChain_revert_unauthorized() public {
        address rando = makeAddr("rando");
        bytes32 recipient = settler.addressToBytes32(agentWallet);

        vm.prank(rando);
        vm.expectRevert("Not authorized");
        settler.settleCrossChain(99, SETTLE_AMOUNT, BASE_DOMAIN, recipient, "");
    }

    function test_setAuthorizedCaller() public {
        address newCaller = makeAddr("newCaller");
        settler.setAuthorizedCaller(newCaller, true);
        assertTrue(settler.authorizedCallers(newCaller));

        settler.setAuthorizedCaller(newCaller, false);
        assertFalse(settler.authorizedCallers(newCaller));
    }
}
