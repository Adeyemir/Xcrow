// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {XcrowEscrow} from "../src/core/XcrowEscrow.sol";
import {XcrowTypes} from "../src/libraries/XcrowTypes.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";

contract XcrowEscrowTest is Test {
    XcrowEscrow public escrow;
    MockUSDC public usdc;
    MockIdentityRegistry public registry;

    address public owner = address(this);
    address public treasury = makeAddr("treasury");
    address public client = makeAddr("client");
    address public agentOwner = makeAddr("agentOwner");
    address public agentWallet = makeAddr("agentWallet");

    uint256 public agentId;
    uint256 public constant JOB_AMOUNT = 100e6; // 100 USDC
    uint256 public constant PROTOCOL_FEE_BPS = 250; // 2.5%
    uint256 public constant DISPUTE_TIMEOUT = 3 days;
    uint256 public constant SETTLEMENT_WINDOW = 30 minutes;

    event JobCreated(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount);

    function setUp() public {
        usdc = new MockUSDC();
        registry = new MockIdentityRegistry();

        escrow = new XcrowEscrow(
            address(usdc), address(registry), treasury, PROTOCOL_FEE_BPS, DISPUTE_TIMEOUT, SETTLEMENT_WINDOW
        );

        // Register a mock agent
        agentId = registry.mockRegisterAgent(agentOwner, agentWallet, "ipfs://agent1");

        // Fund client with USDC
        usdc.mint(client, 10_000e6);

        // Client approves escrow
        vm.prank(client);
        usdc.approve(address(escrow), type(uint256).max);
    }

    // =========================================
    // createJob tests
    // =========================================

    function test_createJob_success() public {
        vm.prank(client);
        uint256 jobId =
            escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("summarize this doc"), block.timestamp + 1 days);

        assertEq(jobId, 1);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(job.agentId, agentId);
        assertEq(job.client, client);
        assertEq(job.agentWallet, agentWallet);
        assertEq(job.amount, JOB_AMOUNT);
        assertEq(job.platformFee, (JOB_AMOUNT * PROTOCOL_FEE_BPS) / 10000);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.InProgress));

        // USDC transferred to escrow
        assertEq(usdc.balanceOf(address(escrow)), JOB_AMOUNT);
        assertEq(usdc.balanceOf(client), 10_000e6 - JOB_AMOUNT);
    }

    function test_createJob_emitsEvent() public {
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit JobCreated(1, agentId, client, JOB_AMOUNT);
        escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("task"), block.timestamp + 1 days);
    }

    function test_createJob_revert_zeroAmount() public {
        vm.prank(client);
        vm.expectRevert("Amount must be > 0");
        escrow.createJob(agentId, 11155111, 0, keccak256("task"), block.timestamp + 1 days);
    }

    function test_createJob_revert_pastDeadline() public {
        vm.prank(client);
        vm.expectRevert("Deadline must be future");
        escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("task"), block.timestamp - 1);
    }

    function test_createJob_revert_emptyTaskHash() public {
        vm.prank(client);
        vm.expectRevert("Task hash required");
        escrow.createJob(agentId, 11155111, JOB_AMOUNT, bytes32(0), block.timestamp + 1 days);
    }

    function test_createJob_revert_noAgentWallet() public {
        // Register agent with zero wallet
        uint256 badAgent = registry.mockRegisterAgent(agentOwner, address(0), "ipfs://bad");
        vm.prank(client);
        vm.expectRevert("Agent has no wallet set");
        escrow.createJob(badAgent, 11155111, JOB_AMOUNT, keccak256("task"), block.timestamp + 1 days);
    }

    function test_createJob_revert_hireYourself() public {
        // Register agent with client as wallet
        uint256 selfAgent = registry.mockRegisterAgent(client, client, "ipfs://self");
        vm.prank(client);
        vm.expectRevert("Cannot hire yourself");
        escrow.createJob(selfAgent, 11155111, JOB_AMOUNT, keccak256("task"), block.timestamp + 1 days);
    }

    function test_createJob_incrementsJobId() public {
        vm.startPrank(client);
        uint256 id1 = escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("a"), block.timestamp + 1 days);
        uint256 id2 = escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("b"), block.timestamp + 1 days);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_createJob_tracksClientAndAgentJobs() public {
        vm.prank(client);
        escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("task"), block.timestamp + 1 days);

        uint256[] memory cJobs = escrow.getClientJobs(client);
        assertEq(cJobs.length, 1);
        assertEq(cJobs[0], 1);

        uint256[] memory aJobs = escrow.getAgentJobs(agentId);
        assertEq(aJobs.length, 1);
        assertEq(aJobs[0], 1);
    }

    // =========================================
    // completeJob tests
    // =========================================

    function test_completeJob_success() public {
        uint256 jobId = _createDefaultJob();

        vm.prank(agentWallet);
        escrow.completeJob(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Completed));
    }

    function test_completeJob_revert_notAgent() public {
        uint256 jobId = _createDefaultJob();

        vm.prank(client);
        vm.expectRevert("Not agent wallet");
        escrow.completeJob(jobId);
    }

    // =========================================
    // settleJob tests
    // =========================================

    function test_settleJob_success() public {
        uint256 jobId = _createAndCompleteJob();

        uint256 expectedFee = (JOB_AMOUNT * PROTOCOL_FEE_BPS) / 10000; // 2.5 USDC
        uint256 expectedPayout = JOB_AMOUNT - expectedFee; // 97.5 USDC

        uint256 agentBalBefore = usdc.balanceOf(agentOwner);

        vm.prank(client);
        escrow.settleJob(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
        assertGt(job.settledAt, 0);

        // Agent got paid
        assertEq(usdc.balanceOf(agentOwner), agentBalBefore + expectedPayout);

        // Fees accumulated
        assertEq(escrow.accumulatedFees(), expectedFee);
    }

    function test_settleJob_revert_notClient() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(agentWallet);
        vm.expectRevert("Only client can settle");
        escrow.settleJob(jobId);
    }

    function test_settleJob_revert_notCompleted() public {
        uint256 jobId = _createDefaultJob();

        vm.prank(client);
        vm.expectRevert("Job not completed");
        escrow.settleJob(jobId);
    }

    function test_settleJob_feeCalculation() public {
        // Test with different amounts
        uint256 amount = 1000e6; // 1000 USDC
        usdc.mint(client, amount);

        vm.prank(client);
        uint256 jobId = escrow.createJob(agentId, 11155111, amount, keccak256("big job"), block.timestamp + 1 days);

        vm.prank(agentWallet);
        escrow.completeJob(jobId);
        vm.prank(client);
        escrow.settleJob(jobId);

        // 2.5% of 1000 = 25 USDC
        assertEq(escrow.accumulatedFees(), 25e6);
    }

    // =========================================
    // cancelJob tests
    // =========================================

    function test_cancelJob_success() public {
        uint256 jobId = _createDefaultJob();
        uint256 clientBalBefore = usdc.balanceOf(client);

        vm.prank(client);
        escrow.cancelJob(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Cancelled));

        // Full refund
        assertEq(usdc.balanceOf(client), clientBalBefore + JOB_AMOUNT);
    }

    function test_cancelJob_revert_afterComplete() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(client);
        vm.expectRevert("Can only cancel InProgress jobs");
        escrow.cancelJob(jobId);
    }

    function test_cancelJob_revert_notClient() public {
        uint256 jobId = _createDefaultJob();

        vm.prank(agentWallet);
        vm.expectRevert("Only client can cancel");
        escrow.cancelJob(jobId);
    }

    // =========================================
    // disputeJob tests
    // =========================================

    function test_disputeJob_byClient() public {
        uint256 jobId = _createDefaultJob();

        vm.prank(client);
        escrow.disputeJob(jobId, "Agent unresponsive");

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Disputed));
    }

    function test_disputeJob_byAgent() public {
        uint256 jobId = _createDefaultJob();

        vm.prank(agentWallet);
        escrow.disputeJob(jobId, "Client changed requirements");

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Disputed));
    }

    function test_disputeJob_revert_outsider() public {
        uint256 jobId = _createDefaultJob();
        address rando = makeAddr("rando");

        vm.prank(rando);
        vm.expectRevert("Only client or agent can dispute");
        escrow.disputeJob(jobId, "not my business");
    }

    function test_disputeJob_revert_settledState() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(client);
        escrow.settleJob(jobId);

        vm.prank(client);
        vm.expectRevert("Cannot dispute in current state");
        escrow.disputeJob(jobId, "reason");
    }

    // =========================================
    // refundExpiredJob tests
    // =========================================

    function test_refundExpiredJob_success() public {
        uint256 jobId = _createDefaultJob();
        uint256 clientBalBefore = usdc.balanceOf(client);

        // Warp past deadline
        vm.warp(block.timestamp + 2 days);

        // Client can refund immediately after deadline
        vm.prank(client);
        escrow.refundExpiredJob(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Expired));
        assertEq(usdc.balanceOf(client), clientBalBefore + JOB_AMOUNT);
    }

    function test_refundExpiredJob_revert_notExpired() public {
        uint256 jobId = _createDefaultJob();

        vm.expectRevert("Job not expired");
        escrow.refundExpiredJob(jobId);
    }

    function test_refundExpiredJob_inProgress() public {
        uint256 jobId = _createDefaultJob();

        vm.warp(block.timestamp + 2 days);

        vm.prank(client);
        escrow.refundExpiredJob(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Expired));
    }

    function test_refundExpiredJob_revert_nonClientBeforeGracePeriod() public {
        uint256 jobId = _createDefaultJob();
        vm.warp(block.timestamp + 2 days);

        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert("Only client can refund before grace period");
        escrow.refundExpiredJob(jobId);
    }

    function test_refundExpiredJob_anyoneAfterGracePeriod() public {
        uint256 jobId = _createDefaultJob();
        uint256 clientBalBefore = usdc.balanceOf(client);

        // Warp past deadline + disputeTimeout grace period
        vm.warp(block.timestamp + 2 days + DISPUTE_TIMEOUT + 1);

        address rando = makeAddr("rando");
        vm.prank(rando);
        escrow.refundExpiredJob(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Expired));
        assertEq(usdc.balanceOf(client), clientBalBefore + JOB_AMOUNT);
    }

    // =========================================
    // Admin tests
    // =========================================

    function test_withdrawFees() public {
        // Complete a job to accumulate fees
        uint256 jobId = _createAndCompleteJob();
        vm.prank(client);
        escrow.settleJob(jobId);

        uint256 expectedFee = (JOB_AMOUNT * PROTOCOL_FEE_BPS) / 10000;
        assertEq(escrow.accumulatedFees(), expectedFee);

        escrow.withdrawFees();

        assertEq(usdc.balanceOf(treasury), expectedFee);
        assertEq(escrow.accumulatedFees(), 0);
    }

    function test_withdrawFees_revert_noFees() public {
        vm.expectRevert("No fees to withdraw");
        escrow.withdrawFees();
    }

    function test_setProtocolFee() public {
        escrow.setProtocolFee(500); // 5%
        assertEq(escrow.protocolFeeBps(), 500);
    }

    function test_setProtocolFee_revert_tooHigh() public {
        vm.expectRevert("Fee too high");
        escrow.setProtocolFee(1001); // >10%
    }

    function test_pause_blocksCreateJob() public {
        escrow.pause();

        vm.prank(client);
        vm.expectRevert();
        escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("task"), block.timestamp + 1 days);
    }

    // =========================================
    // disputeJob resolution tests
    // =========================================

    function test_resolveDispute_afterTimeout() public {
        uint256 jobId = _createDefaultJob();
        uint256 clientBalBefore = usdc.balanceOf(client);

        vm.prank(client);
        escrow.disputeJob(jobId, "Agent unresponsive");

        // Warp past dispute timeout
        vm.warp(block.timestamp + DISPUTE_TIMEOUT + 1);

        vm.prank(client);
        escrow.resolveDispute(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Refunded));
        assertEq(usdc.balanceOf(client), clientBalBefore + JOB_AMOUNT);
    }

    function test_resolveDispute_revert_beforeTimeout() public {
        uint256 jobId = _createDefaultJob();

        vm.prank(client);
        escrow.disputeJob(jobId, "reason");

        vm.prank(client);
        vm.expectRevert("Dispute timeout not elapsed");
        escrow.resolveDispute(jobId);
    }

    function test_resolveDisputeByOwner_favorAgent() public {
        uint256 jobId = _createDefaultJob();
        uint256 agentBalBefore = usdc.balanceOf(agentOwner);

        vm.prank(client);
        escrow.disputeJob(jobId, "disagreement");

        uint256 expectedFee = (JOB_AMOUNT * PROTOCOL_FEE_BPS) / 10000;
        uint256 expectedPayout = JOB_AMOUNT - expectedFee;

        // Owner resolves in favor of agent
        escrow.resolveDisputeByOwner(jobId, true);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
        assertEq(usdc.balanceOf(agentOwner), agentBalBefore + expectedPayout);
        assertEq(escrow.accumulatedFees(), expectedFee);
    }

    function test_resolveDisputeByOwner_favorClient() public {
        uint256 jobId = _createDefaultJob();
        uint256 clientBalBefore = usdc.balanceOf(client);

        vm.prank(client);
        escrow.disputeJob(jobId, "terrible work");

        // Owner resolves in favor of client
        escrow.resolveDisputeByOwner(jobId, false);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Refunded));
        assertEq(usdc.balanceOf(client), clientBalBefore + JOB_AMOUNT);
    }

    function test_resolveDisputeByOwner_revert_notOwner() public {
        uint256 jobId = _createDefaultJob();

        vm.prank(client);
        escrow.disputeJob(jobId, "reason");

        vm.prank(client);
        vm.expectRevert();
        escrow.resolveDisputeByOwner(jobId, true);
    }

    // =========================================
    // Full lifecycle test
    // =========================================

    function test_fullLifecycle() public {
        // 1. Client creates job (starts as InProgress)
        vm.prank(client);
        uint256 jobId =
            escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("full test"), block.timestamp + 1 days);

        // 2. Agent completes
        vm.prank(agentWallet);
        escrow.completeJob(jobId);

        // 3. Agent submits proof of work
        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("output"));

        // 4. Settlement window elapses
        vm.warp(block.timestamp + SETTLEMENT_WINDOW + 1);

        // 5. Auto-settle
        escrow.autoSettle(jobId);

        // Verify final state
        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));

        uint256 expectedFee = (JOB_AMOUNT * PROTOCOL_FEE_BPS) / 10000;
        uint256 expectedPayout = JOB_AMOUNT - expectedFee;

        assertEq(usdc.balanceOf(agentOwner), expectedPayout);
        assertEq(escrow.accumulatedFees(), expectedFee);

        // 6. Owner withdraws fees
        escrow.withdrawFees();
        assertEq(usdc.balanceOf(treasury), expectedFee);
    }

    // =========================================
    // createCrossChainJob tests
    // =========================================

    function test_createCrossChainJob_success() public {
        vm.prank(client);
        uint256 jobId = escrow.createCrossChainJob(
            agentId, 11155111, JOB_AMOUNT, keccak256("cross-chain task"), block.timestamp + 1 days, 6
        );

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(job.amount, JOB_AMOUNT);
        assertTrue(job.isCrossChain);
        assertEq(job.destinationDomain, 6);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.InProgress));
    }

    function test_createCrossChainJob_revert_zeroDomain() public {
        vm.prank(client);
        vm.expectRevert("Invalid destination domain");
        escrow.createCrossChainJob(agentId, 11155111, JOB_AMOUNT, keccak256("task"), block.timestamp + 1 days, 0);
    }

    function test_createCrossChainJob_fullLifecycle() public {
        vm.prank(client);
        uint256 jobId = escrow.createCrossChainJob(
            agentId, 11155111, JOB_AMOUNT, keccak256("cc task"), block.timestamp + 1 days, 6
        );

        vm.prank(agentWallet);
        escrow.completeJob(jobId);
        vm.prank(client);
        escrow.settleJob(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
        assertTrue(job.isCrossChain);
    }

    // =========================================
    // Helpers
    // =========================================

    function _createDefaultJob() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(agentId, 11155111, JOB_AMOUNT, keccak256("test task"), block.timestamp + 1 days);
    }

    function _createAndCompleteJob() internal returns (uint256) {
        uint256 jobId = _createDefaultJob();
        vm.prank(agentWallet);
        escrow.completeJob(jobId);
        return jobId;
    }

    // =========================================
    // submitProofOfWork tests
    // =========================================

    function test_submitProofOfWork_success() public {
        uint256 jobId = _createAndCompleteJob();
        bytes32 proofHash = keccak256("output content");

        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, proofHash);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(job.proofOfWorkHash, proofHash);
        assertGt(job.proofSubmittedAt, 0);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Completed)); // status unchanged
    }

    function test_submitProofOfWork_revert_notAgent() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(client);
        vm.expectRevert("Not agent wallet");
        escrow.submitProofOfWork(jobId, keccak256("proof"));
    }

    function test_submitProofOfWork_revert_notCompleted() public {
        uint256 jobId = _createDefaultJob(); // InProgress, not Completed

        vm.prank(agentWallet);
        vm.expectRevert("Job not completed");
        escrow.submitProofOfWork(jobId, keccak256("proof"));
    }

    function test_submitProofOfWork_revert_alreadySubmitted() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("proof"));

        vm.prank(agentWallet);
        vm.expectRevert("Proof already submitted");
        escrow.submitProofOfWork(jobId, keccak256("different proof"));
    }

    function test_submitProofOfWork_revert_emptyHash() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(agentWallet);
        vm.expectRevert("Proof hash required");
        escrow.submitProofOfWork(jobId, bytes32(0));
    }

    // =========================================
    // autoSettle tests
    // =========================================

    function test_autoSettle_success() public {
        uint256 jobId = _createAndCompleteJob();
        bytes32 proofHash = keccak256("output");

        uint256 expectedFee = (JOB_AMOUNT * PROTOCOL_FEE_BPS) / 10000;
        uint256 expectedPayout = JOB_AMOUNT - expectedFee;
        uint256 agentBalBefore = usdc.balanceOf(agentOwner);

        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, proofHash);

        // Warp past settlement window
        vm.warp(block.timestamp + SETTLEMENT_WINDOW + 1);

        address rando = makeAddr("rando");
        vm.prank(rando);
        escrow.autoSettle(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
        assertGt(job.settledAt, 0);
        assertEq(usdc.balanceOf(agentOwner), agentBalBefore + expectedPayout);
        assertEq(escrow.accumulatedFees(), expectedFee);
    }

    function test_autoSettle_revert_noProof() public {
        uint256 jobId = _createAndCompleteJob();

        vm.warp(block.timestamp + SETTLEMENT_WINDOW + 1);

        vm.expectRevert("No proof of work submitted");
        escrow.autoSettle(jobId);
    }

    function test_autoSettle_revert_windowNotElapsed() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("proof"));

        // Try immediately — window not elapsed
        vm.expectRevert("Settlement window not elapsed");
        escrow.autoSettle(jobId);
    }

    function test_autoSettle_revert_windowNotElapsed_justBefore() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("proof"));

        // Warp to 1 second before window closes
        vm.warp(block.timestamp + SETTLEMENT_WINDOW - 1);

        vm.expectRevert("Settlement window not elapsed");
        escrow.autoSettle(jobId);
    }

    function test_autoSettle_revert_afterDispute() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("proof"));

        // Client disputes before window elapses
        vm.prank(client);
        escrow.disputeJob(jobId, "output is wrong");

        vm.warp(block.timestamp + SETTLEMENT_WINDOW + 1);

        // autoSettle must fail — job is now Disputed, not Completed
        vm.expectRevert("Job not completed");
        escrow.autoSettle(jobId);
    }

    function test_autoSettle_agentCanCallSelf() public {
        uint256 jobId = _createAndCompleteJob();

        vm.prank(agentWallet);
        escrow.submitProofOfWork(jobId, keccak256("proof"));

        vm.warp(block.timestamp + SETTLEMENT_WINDOW + 1);

        // Agent calls autoSettle on their own job
        vm.prank(agentWallet);
        escrow.autoSettle(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
    }

    function test_autoSettle_clientCanStillManualSettle_beforePoW() public {
        uint256 jobId = _createAndCompleteJob();

        // Client settles manually without waiting for PoW — still works
        vm.prank(client);
        escrow.settleJob(jobId);

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(XcrowTypes.JobStatus.Settled));
    }
}
