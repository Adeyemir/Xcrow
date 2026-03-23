// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {XcrowEscrow} from "../src/core/XcrowEscrow.sol";
import {ReputationPricer} from "../src/core/ReputationPricer.sol";
import {CrossChainSettler} from "../src/core/CrossChainSettler.sol";
import {XcrowRouter} from "../src/core/XcrowRouter.sol";
import {XcrowTypes} from "../src/libraries/XcrowTypes.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";
import {MockReputationRegistry} from "./mocks/MockReputationRegistry.sol";
import {MockTokenMessenger} from "./mocks/MockCCTP.sol";

contract XcrowRouterTest is Test {
    XcrowEscrow public escrow;
    ReputationPricer public pricer;
    CrossChainSettler public settler;
    XcrowRouter public router;
    MockUSDC public usdc;
    MockIdentityRegistry public identityReg;
    MockReputationRegistry public reputationReg;
    MockTokenMessenger public messenger;

    address public owner = address(this);
    address public treasury = makeAddr("treasury");
    address public client = makeAddr("client");
    address public agentOwner = makeAddr("agentOwner");
    address public agentWallet = makeAddr("agentWallet");

    uint256 public agentId;
    uint256 public constant PROTOCOL_FEE_BPS = 250;
    uint256 public constant SETTLEMENT_WINDOW = 30 minutes;

    event AgentHired(
        uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount, bool crossChain
    );

    function setUp() public {
        usdc = new MockUSDC();
        identityReg = new MockIdentityRegistry();
        reputationReg = new MockReputationRegistry(address(identityReg));
        messenger = new MockTokenMessenger();

        // Deploy core contracts
        escrow =
            new XcrowEscrow(address(usdc), address(identityReg), treasury, PROTOCOL_FEE_BPS, 3 days, SETTLEMENT_WINDOW);

        pricer = new ReputationPricer(
            address(reputationReg),
            address(identityReg),
            20000, // 2x max premium
            100, // max score
            3, // min reviews
            "starred"
        );

        settler = new CrossChainSettler(
            address(usdc),
            address(messenger),
            0 // Sepolia domain
        );

        router = new XcrowRouter(
            address(usdc),
            address(escrow),
            address(pricer),
            address(settler),
            address(identityReg),
            address(reputationReg),
            11155111 // Sepolia chainId
        );

        // Register agent
        agentId = identityReg.mockRegisterAgent(agentOwner, agentWallet, "ipfs://agent");

        // Set base rate for pricer
        vm.prank(agentOwner);
        pricer.setBaseRate(agentId, 10e6); // 10 USDC

        // Add trusted reviewer for pricer
        pricer.addTrustedReviewer(client);

        // Configure settler domain
        settler.configureDomain(6, true, bytes32(0)); // Base Sepolia

        // Authorize router to call settler
        settler.setAuthorizedCaller(address(router), true);

        // Fund client
        usdc.mint(client, 10_000e6);
    }

    // =========================================
    // View function tests (no delegation issues)
    // =========================================

    function test_getQuote_viaPricer() public view {
        XcrowTypes.PriceQuote memory quote = router.getQuote(agentId);

        assertEq(quote.agentId, agentId);
        assertEq(quote.baseRate, 10e6);
        // No reputation reviews yet, so 1x
        assertEq(quote.multiplier, 10000);
        assertEq(quote.effectiveRate, 10e6);
    }

    function test_getQuote_withReputation() public {
        reputationReg.mockSetSummary(agentId, 10, 80, 0);

        XcrowTypes.PriceQuote memory quote = router.getQuote(agentId);

        // 2.6x multiplier (80/100 * 2x premium + 1x base)
        assertEq(quote.multiplier, 26000);
        assertEq(quote.effectiveRate, 26e6); // 10 * 2.6
    }

    function test_getAgentInfo() public view {
        (address agentOwnerResult, address wallet, string memory uri) = router.getAgentInfo(agentId);

        assertEq(agentOwnerResult, agentOwner);
        assertEq(wallet, agentWallet);
        assertEq(uri, "ipfs://agent");
    }

    function test_estimateCrossChainFee() public view {
        uint256 fee = router.estimateCrossChainFee(100e6, 6);
        assertEq(fee, messenger.MOCK_MIN_FEE());
    }

    // =========================================
    // hireAgent tests
    // =========================================

    function test_hireAgent_createsEscrowJob() public {
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);

        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("summarize this"), block.timestamp + 1 days);
        vm.stopPrank();

        assertEq(jobId, 1);

        // Job exists in escrow — note: client is the ROUTER, not the end user
        // This is the delegation pattern — router acts on behalf of user
        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(job.agentId, agentId);
        assertEq(job.amount, 100e6);
        assertEq(job.client, address(router)); // Router is the escrow client
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.InProgress));

        // USDC moved from client → router → escrow
        assertEq(usdc.balanceOf(address(escrow)), 100e6);
    }

    function test_hireAgent_emitsEvent() public {
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);

        vm.expectEmit(true, true, true, true);
        emit AgentHired(1, agentId, client, 100e6, false);

        router.hireAgent(agentId, 100e6, keccak256("task"), block.timestamp + 1 days);
        vm.stopPrank();
    }

    function test_hireAgentWithQuote_createsQuotedJob() public {
        reputationReg.mockSetSummary(agentId, 10, 80, 0);

        // Get expected quote
        XcrowTypes.PriceQuote memory expectedQuote = router.getQuote(agentId);
        // effectiveRate = 26e6 — only this amount is pulled from user now

        vm.startPrank(client);
        usdc.approve(address(router), expectedQuote.effectiveRate);

        (uint256 jobId, XcrowTypes.PriceQuote memory quote) =
            router.hireAgentWithQuote(agentId, keccak256("premium task"), block.timestamp + 1 days);
        vm.stopPrank();

        assertEq(jobId, 1);
        assertEq(quote.effectiveRate, 26e6);
        assertEq(quote.multiplier, 26000);

        // Job amount in escrow = effectiveRate
        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(job.amount, 26e6);

        // No USDC trapped in router
        assertEq(usdc.balanceOf(address(router)), 0);
    }

    // =========================================
    // Full flow via Router delegation
    // =========================================

    function test_router_settleAndPay_delegation() public {
        // Client hires agent via router
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("settle test"), block.timestamp + 1 days);
        vm.stopPrank();

        // Agent accepts and completes (on escrow directly — job.client is router)
        vm.prank(agentWallet);
        escrow.completeJob(jobId);

        // Client settles via router — should work because originalClient[jobId] = client
        vm.prank(client);
        router.settleAndPay(jobId, 0, "");

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));

        // Agent got paid (100 - 2.5% = 97.5)
        assertEq(usdc.balanceOf(agentWallet), 97_500_000);
    }

    function test_router_submitFeedback_delegation() public {
        // Full lifecycle via router
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("feedback test"), block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(agentWallet);
        escrow.completeJob(jobId);

        vm.prank(client);
        router.settleAndPay(jobId, 0, "");

        // Client submits feedback via router — originalClient check
        vm.prank(client);
        router.submitFeedback(jobId, 90, 0, "quality", "ipfs://feedback", keccak256("feedback"));

        // Feedback recorded under router address (since router calls reputationReg)
        // Index is 2: settleAndPay auto-submits proof-of-payment (index 1), submitFeedback adds the rating (index 2)
        uint64 lastIdx = reputationReg.getLastIndex(agentId, address(router));
        assertEq(lastIdx, 2);
    }

    function test_router_settleAndPay_revert_notClient() public {
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("test"), block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(agentWallet);
        escrow.completeJob(jobId);

        // Random user tries to settle — should fail
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert("Only client can settle");
        router.settleAndPay(jobId, 0, "");
    }

    // =========================================
    // Direct escrow flow (unchanged, for reference)
    // =========================================

    function test_directEscrow_fullLifecycle() public {
        // Client creates job directly on escrow
        vm.startPrank(client);
        usdc.approve(address(escrow), 100e6);
        uint256 jobId = escrow.createJob(agentId, 11155111, 100e6, keccak256("direct"), block.timestamp + 1 days);
        vm.stopPrank();

        // Agent accepts and completes
        vm.prank(agentWallet);
        escrow.completeJob(jobId);

        // Client settles
        vm.prank(client);
        escrow.settleJob(jobId);

        // Verify
        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
        assertEq(job.client, client); // Direct client, not router

        // Agent got paid (100 - 2.5% fee = 97.5)
        assertEq(usdc.balanceOf(agentWallet), 97_500_000);
    }

    function test_directEscrow_withFeedback() public {
        // Full cycle via direct escrow
        vm.startPrank(client);
        usdc.approve(address(escrow), 100e6);
        uint256 jobId = escrow.createJob(agentId, 11155111, 100e6, keccak256("feedback test"), block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(agentWallet);
        escrow.completeJob(jobId);
        vm.prank(client);
        escrow.settleJob(jobId);

        // Submit feedback directly — router delegation makes msg.sender = router, not client
        vm.prank(client);
        reputationReg.giveFeedback(
            agentId,
            85, // value
            0, // decimals
            "quality",
            "",
            "",
            "ipfs://feedback1",
            keccak256("feedback content")
        );

        // Verify feedback was recorded under client's address
        uint64 lastIdx = reputationReg.getLastIndex(agentId, client);
        assertEq(lastIdx, 1);
    }

    // =========================================
    // Admin tests
    // =========================================

    function test_updateEscrow() public {
        XcrowEscrow newEscrow =
            new XcrowEscrow(address(usdc), address(identityReg), treasury, 250, 3 days, SETTLEMENT_WINDOW);
        router.updateEscrow(address(newEscrow));
        assertEq(address(router.escrow()), address(newEscrow));
    }

    function test_updatePricer() public {
        ReputationPricer newPricer =
            new ReputationPricer(address(reputationReg), address(identityReg), 20000, 100, 3, "starred");
        router.updatePricer(address(newPricer));
        assertEq(address(router.pricer()), address(newPricer));
    }

    function test_pause_blocksHire() public {
        router.pause();

        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        vm.expectRevert();
        router.hireAgent(agentId, 100e6, keccak256("task"), block.timestamp + 1 days);
        vm.stopPrank();
    }

    function test_onlyOwner_updateEscrow() public {
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert();
        router.updateEscrow(address(1));
    }

    // =========================================
    // Cross-chain hiring via Router
    // =========================================

    function test_hireAgentCrossChain_success() public {
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgentCrossChain(agentId, 100e6, keccak256("cc task"), block.timestamp + 1 days, 6);
        vm.stopPrank();

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(job.amount, 100e6);
        assertTrue(job.isCrossChain);
        assertEq(job.destinationDomain, 6);
        assertEq(router.originalClient(jobId), client);
    }

    function test_hireAgentCrossChain_lifecycle() public {
        // Hire cross-chain
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId =
            router.hireAgentCrossChain(agentId, 100e6, keccak256("cc lifecycle"), block.timestamp + 1 days, 6);
        vm.stopPrank();

        // Agent accepts and completes
        vm.prank(agentWallet);
        escrow.completeJob(jobId);

        // Client settles via router (same-chain settle, cross-chain bridging would need funded router)
        vm.prank(client);
        router.settleAndPay(jobId, 0, "");

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
    }

    function test_cancelJobViaRouter_success() public {
        // Setup: Hire via router
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("cancel task"), block.timestamp + 1 days);
        vm.stopPrank();

        // Verify router ownership
        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(job.client, address(router));
        assertEq(router.originalClient(jobId), client);

        // Cancel via router
        vm.prank(client);
        router.cancelJobViaRouter(jobId);

        // Verify status
        job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Cancelled));

        // Verify refund (client balance should restore to original 10,000e6)
        assertEq(usdc.balanceOf(client), 10_000e6);
    }

    function test_disputeJobViaRouter_success() public {
        // Setup: Hire via router
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("dispute task"), block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(client);
        router.disputeJobViaRouter(jobId, "not done");

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Disputed));
    }

    // =========================================
    // autoSettleViaRouter tests
    // =========================================

    function test_autoSettleViaRouter_success() public {
        // Hire via router
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("auto settle task"), block.timestamp + 1 days);
        vm.stopPrank();

        // Agent accepts, completes, submits PoW directly on escrow
        vm.prank(agentWallet);
        escrow.completeJob(jobId);
        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("audit report output"));

        // Warp past settlement window
        vm.warp(block.timestamp + SETTLEMENT_WINDOW + 1);

        // Agent triggers auto-settlement via router (also emits ERC-8004 feedback)
        vm.prank(agentWallet);
        router.autoSettleViaRouter(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
        // Agent got paid (100 - 2.5% = 97.5)
        assertEq(usdc.balanceOf(agentWallet), 97_500_000);
    }

    function test_autoSettleViaRouter_revert_windowNotElapsed() public {
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("task"), block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(agentWallet);
        escrow.completeJob(jobId);
        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("proof"));

        // Try before window elapses
        vm.prank(agentWallet);
        vm.expectRevert("Settlement window not elapsed");
        router.autoSettleViaRouter(jobId);
    }

    function test_autoSettleViaRouter_revert_noProof() public {
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("task"), block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(agentWallet);
        escrow.completeJob(jobId);

        vm.warp(block.timestamp + SETTLEMENT_WINDOW + 1);

        vm.expectRevert("No proof of work submitted");
        router.autoSettleViaRouter(jobId);
    }

    function test_autoSettleViaRouter_revert_afterClientDispute() public {
        vm.startPrank(client);
        usdc.approve(address(router), 100e6);
        uint256 jobId = router.hireAgent(agentId, 100e6, keccak256("task"), block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(agentWallet);
        escrow.completeJob(jobId);
        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("proof"));

        // Client disputes before window elapses
        vm.prank(client);
        router.disputeJobViaRouter(jobId, "bad output");

        vm.warp(block.timestamp + SETTLEMENT_WINDOW + 1);

        // autoSettle blocked because job is now Disputed
        vm.expectRevert("Job not completed");
        router.autoSettleViaRouter(jobId);
    }
}
