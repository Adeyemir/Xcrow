// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {XcrowTypes} from "../libraries/XcrowTypes.sol";
import {IXcrowEscrow} from "../interfaces/IXcrowEscrow.sol";
import {IERC8004Identity} from "../interfaces/IERC8004Identity.sol";

/// @title XcrowEscrow
/// @notice USDC escrow for ERC-8004 agent jobs
/// @dev Holds USDC during task execution, releases on completion
contract XcrowEscrow is IXcrowEscrow, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // --- State ---
    IERC20 public immutable usdc;
    IERC8004Identity public immutable identityRegistry;

    uint256 public nextJobId;
    uint256 public protocolFeeBps; // Basis points (250 = 2.5%)
    uint256 public constant MAX_FEE_BPS = 1000; // 10% max
    address public treasury;
    uint256 public disputeTimeout; // Seconds before auto-refund on dispute
    uint256 public settlementWindow; // Seconds after PoW submission before auto-settlement is allowed

    mapping(uint256 => XcrowTypes.Job) public jobs;
    mapping(address => uint256[]) public clientJobs;
    mapping(uint256 => uint256[]) public agentJobs; // agentId => jobIds
    mapping(address => uint256[]) public agentWalletJobs; // agentWallet => jobIds

    // Accumulated protocol fees ready for withdrawal
    uint256 public accumulatedFees;

    // --- Constructor ---
    constructor(
        address _usdc,
        address _identityRegistry,
        address _treasury,
        uint256 _protocolFeeBps,
        uint256 _disputeTimeout,
        uint256 _settlementWindow
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_identityRegistry != address(0), "Invalid registry");
        require(_treasury != address(0), "Invalid treasury");
        require(_protocolFeeBps <= MAX_FEE_BPS, "Fee too high");

        usdc = IERC20(_usdc);
        identityRegistry = IERC8004Identity(_identityRegistry);
        treasury = _treasury;
        protocolFeeBps = _protocolFeeBps;
        disputeTimeout = _disputeTimeout;
        settlementWindow = _settlementWindow;
        nextJobId = 1;
    }

    // --- Internal Helpers ---

    /// @notice Resolve the payout address for a job — always the agent owner's wallet
    /// @dev Agent wallet signs completions; owner wallet receives payment
    function _resolvePayoutAddress(uint256 agentId) internal view returns (address) {
        address ownerAddr = identityRegistry.ownerOf(agentId);
        require(ownerAddr != address(0), "Agent owner not found");
        return ownerAddr;
    }

    // --- Core Functions ---

    /// @notice Create a job by specifying the agent's wallet address directly
    /// @dev agentId is required so payout can be routed to the agent owner
    function createJobByWallet(
        address agentWallet,
        uint256 amount,
        bytes32 taskHash,
        uint256 deadline,
        uint256 agentId
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 jobId)
    {
        require(amount > 0, "Amount must be > 0");
        require(deadline > block.timestamp, "Deadline must be future");
        require(taskHash != bytes32(0), "Task hash required");
        require(agentWallet != address(0), "Invalid agent wallet");
        require(agentId > 0, "Agent ID required");

        uint256 platformFee = (amount * protocolFeeBps) / 10000;
        jobId = nextJobId++;

        jobs[jobId] = XcrowTypes.Job({
            jobId: jobId,
            agentId: agentId,
            agentChainId: uint32(block.chainid),
            client: msg.sender,
            agentWallet: agentWallet,
            amount: amount,
            platformFee: platformFee,
            taskHash: taskHash,
            deadline: deadline,
            createdAt: block.timestamp,
            settledAt: 0,
            proofOfWorkHash: bytes32(0),
            proofSubmittedAt: 0,
            status: XcrowTypes.JobStatus.InProgress,
            isCrossChain: false,
            destinationDomain: 0
        });

        clientJobs[msg.sender].push(jobId);
        agentJobs[agentId].push(jobId);
        agentWalletJobs[agentWallet].push(jobId);

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit JobCreated(jobId, agentId, msg.sender, amount);
    }

    /// @inheritdoc IXcrowEscrow
    function createJob(uint256 agentId, uint32 agentChainId, uint256 amount, bytes32 taskHash, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 jobId)
    {
        require(amount > 0, "Amount must be > 0");
        require(deadline > block.timestamp, "Deadline must be future");
        require(taskHash != bytes32(0), "Task hash required");

        // Resolve agent's payment wallet from ERC-8004
        address agentWallet = identityRegistry.getAgentWallet(agentId);
        require(agentWallet != address(0), "Agent has no wallet set");
        require(agentWallet != msg.sender, "Cannot hire yourself");

        // Calculate fee
        uint256 platformFee = (amount * protocolFeeBps) / 10000;

        jobId = nextJobId++;

        jobs[jobId] = XcrowTypes.Job({
            jobId: jobId,
            agentId: agentId,
            agentChainId: agentChainId,
            client: msg.sender,
            agentWallet: agentWallet,
            amount: amount,
            platformFee: platformFee,
            taskHash: taskHash,
            deadline: deadline,
            createdAt: block.timestamp,
            settledAt: 0,
            proofOfWorkHash: bytes32(0),
            proofSubmittedAt: 0,
            status: XcrowTypes.JobStatus.InProgress,
            isCrossChain: false,
            destinationDomain: 0
        });

        clientJobs[msg.sender].push(jobId);
        agentJobs[agentId].push(jobId);
        agentWalletJobs[agentWallet].push(jobId);

        // Transfer USDC from client to escrow
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit JobCreated(jobId, agentId, msg.sender, amount);
    }

    /// @notice Create a cross-chain escrow job (agent will be paid on destination chain)
    function createCrossChainJob(
        uint256 agentId,
        uint32 agentChainId,
        uint256 amount,
        bytes32 taskHash,
        uint256 deadline,
        uint32 destinationDomain
    ) external nonReentrant whenNotPaused returns (uint256 jobId) {
        require(amount > 0, "Amount must be > 0");
        require(deadline > block.timestamp, "Deadline must be in future");
        require(taskHash != bytes32(0), "Task hash required");
        require(destinationDomain > 0, "Invalid destination domain");

        address agentWallet = identityRegistry.getAgentWallet(agentId);
        require(agentWallet != address(0), "Agent has no wallet set");
        require(agentWallet != msg.sender, "Cannot hire yourself");

        uint256 platformFee = (amount * protocolFeeBps) / 10000;

        jobId = nextJobId++;

        jobs[jobId] = XcrowTypes.Job({
            jobId: jobId,
            agentId: agentId,
            agentChainId: agentChainId,
            client: msg.sender,
            agentWallet: agentWallet,
            amount: amount,
            platformFee: platformFee,
            taskHash: taskHash,
            deadline: deadline,
            createdAt: block.timestamp,
            settledAt: 0,
            proofOfWorkHash: bytes32(0),
            proofSubmittedAt: 0,
            status: XcrowTypes.JobStatus.InProgress,
            isCrossChain: true,
            destinationDomain: destinationDomain
        });

        clientJobs[msg.sender].push(jobId);
        agentJobs[agentId].push(jobId);
        agentWalletJobs[agentWallet].push(jobId);

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit JobCreated(jobId, agentId, msg.sender, amount);
    }

    /// @notice Agent rejects a job — refund goes to refundRecipient (caller handles auth)
    function rejectJob(uint256 jobId, address refundRecipient) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.InProgress, "Job not in progress");

        job.status = XcrowTypes.JobStatus.Cancelled;

        usdc.safeTransfer(refundRecipient, job.amount);

        emit JobCancelled(jobId);
    }

    /// @inheritdoc IXcrowEscrow
    function completeJob(uint256 jobId) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.InProgress, "Job not in progress");
        require(job.agentWallet == msg.sender, "Not agent wallet");

        job.status = XcrowTypes.JobStatus.Completed;
        emit JobCompleted(jobId);
    }

    /// @notice Agent submits proof of work — anchors output hash on-chain and starts the settlement window
    /// @param jobId The job to submit proof for
    /// @param proofHash keccak256 hash of the agent's output (e.g., hash of IPFS CID or output content)
    function submitProofOfWork(uint256 jobId, bytes32 proofHash) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.Completed, "Job not completed");
        require(job.agentWallet == msg.sender, "Not agent wallet");
        require(job.proofSubmittedAt == 0, "Proof already submitted");
        require(proofHash != bytes32(0), "Proof hash required");

        job.proofOfWorkHash = proofHash;
        job.proofSubmittedAt = block.timestamp;

        emit ProofOfWorkSubmitted(jobId, msg.sender, proofHash);
    }

    /// @notice Trustlessly settle a completed job once the settlement window has elapsed after PoW submission
    /// @dev Client's only recourse is to call disputeJob before the window expires
    /// @param jobId The job to auto-settle
    function autoSettle(uint256 jobId) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.Completed, "Job not completed");
        require(job.proofSubmittedAt > 0, "No proof of work submitted");
        require(block.timestamp >= job.proofSubmittedAt + settlementWindow, "Settlement window not elapsed");

        uint256 agentPayout = job.amount - job.platformFee;
        address payoutAddress = _resolvePayoutAddress(job.agentId);

        job.status = XcrowTypes.JobStatus.Settled;
        job.settledAt = block.timestamp;
        accumulatedFees += job.platformFee;

        usdc.safeTransfer(payoutAddress, agentPayout);

        emit JobSettled(jobId, agentPayout, job.platformFee);
    }

    /// @inheritdoc IXcrowEscrow
    function settleJob(uint256 jobId) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.Completed, "Job not completed");
        require(msg.sender == job.client, "Only client can settle");

        uint256 agentPayout = job.amount - job.platformFee;
        address payoutAddress = _resolvePayoutAddress(job.agentId);

        job.status = XcrowTypes.JobStatus.Settled;
        job.settledAt = block.timestamp;

        // Accumulate protocol fees
        accumulatedFees += job.platformFee;

        // Pay the agent owner
        usdc.safeTransfer(payoutAddress, agentPayout);

        emit JobSettled(jobId, agentPayout, job.platformFee);
    }

    /// @notice Platform completes and settles a job in one atomic transaction
    /// @dev Only callable by the contract owner (platform). Used for automatic settlement after agent delivers output.
    /// @param jobId The job to complete and settle
    function completeAndSettle(uint256 jobId) external nonReentrant onlyOwner {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.InProgress, "Job not in progress");

        uint256 agentPayout = job.amount - job.platformFee;
        address payoutAddress = _resolvePayoutAddress(job.agentId);

        job.status = XcrowTypes.JobStatus.Settled;
        job.settledAt = block.timestamp;
        accumulatedFees += job.platformFee;

        usdc.safeTransfer(payoutAddress, agentPayout);

        emit JobCompleted(jobId);
        emit JobSettled(jobId, agentPayout, job.platformFee);
    }

    /// @inheritdoc IXcrowEscrow
    function disputeJob(uint256 jobId, string calldata reason) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(
            job.status == XcrowTypes.JobStatus.InProgress || job.status == XcrowTypes.JobStatus.Completed,
            "Cannot dispute in current state"
        );
        require(msg.sender == job.client || msg.sender == job.agentWallet, "Only client or agent can dispute");

        job.status = XcrowTypes.JobStatus.Disputed;
        emit JobDisputed(jobId, msg.sender, reason);
    }

    /// @inheritdoc IXcrowEscrow
    function cancelJob(uint256 jobId) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.InProgress, "Can only cancel InProgress jobs");
        require(msg.sender == job.client, "Only client can cancel");

        job.status = XcrowTypes.JobStatus.Cancelled;

        // Full refund
        usdc.safeTransfer(job.client, job.amount);

        emit JobCancelled(jobId);
    }

    /// @notice Resolve a disputed job after the dispute timeout has elapsed
    /// @dev Auto-refunds the client if no resolution after disputeTimeout seconds
    function resolveDispute(uint256 jobId) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.Disputed, "Job not disputed");
        require(
            msg.sender == job.client || msg.sender == job.agentWallet || msg.sender == owner(),
            "Not authorized to resolve"
        );

        // After disputeTimeout, anyone authorized can trigger auto-refund
        require(block.timestamp > job.createdAt + disputeTimeout, "Dispute timeout not elapsed");

        job.status = XcrowTypes.JobStatus.Refunded;

        // Full refund to client
        usdc.safeTransfer(job.client, job.amount);

        emit JobRefunded(jobId, job.amount);
    }

    /// @notice Owner can resolve a dispute in favor of agent or client before timeout
    /// @param jobId Job ID
    /// @param favorAgent If true, pay agent; if false, refund client
    function resolveDisputeByOwner(uint256 jobId, bool favorAgent) external nonReentrant onlyOwner {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.Disputed, "Job not disputed");

        if (favorAgent) {
            uint256 agentPayout = job.amount - job.platformFee;
            address payoutAddress = _resolvePayoutAddress(job.agentId);
            job.status = XcrowTypes.JobStatus.Settled;
            job.settledAt = block.timestamp;
            accumulatedFees += job.platformFee;
            usdc.safeTransfer(payoutAddress, agentPayout);
            emit JobSettled(jobId, agentPayout, job.platformFee);
        } else {
            job.status = XcrowTypes.JobStatus.Refunded;
            usdc.safeTransfer(job.client, job.amount);
            emit JobRefunded(jobId, job.amount);
        }
    }

    /// @inheritdoc IXcrowEscrow
    function refundExpiredJob(uint256 jobId) external nonReentrant {
        XcrowTypes.Job storage job = jobs[jobId];
        require(job.status == XcrowTypes.JobStatus.InProgress, "Cannot refund in current state");
        require(block.timestamp > job.deadline, "Job not expired");
        // Only client can refund immediately; others must wait an extra grace period
        require(
            msg.sender == job.client || block.timestamp > job.deadline + disputeTimeout,
            "Only client can refund before grace period"
        );

        job.status = XcrowTypes.JobStatus.Expired;

        // Full refund to client
        usdc.safeTransfer(job.client, job.amount);

        emit JobRefunded(jobId, job.amount);
    }

    // --- View Functions ---

    /// @inheritdoc IXcrowEscrow
    function getJob(uint256 jobId) external view returns (XcrowTypes.Job memory) {
        return jobs[jobId];
    }

    /// @inheritdoc IXcrowEscrow
    function getClientJobs(address client) external view returns (uint256[] memory) {
        return clientJobs[client];
    }

    /// @inheritdoc IXcrowEscrow
    function getAgentJobs(uint256 agentId) external view returns (uint256[] memory) {
        return agentJobs[agentId];
    }

    function getAgentWalletJobs(address wallet) external view returns (uint256[] memory) {
        return agentWalletJobs[wallet];
    }

    // --- Admin Functions ---

    function setProtocolFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "Fee too high");
        protocolFeeBps = newFeeBps;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury");
        treasury = newTreasury;
    }

    function setDisputeTimeout(uint256 newTimeout) external onlyOwner {
        disputeTimeout = newTimeout;
    }

    function withdrawFees() external onlyOwner {
        uint256 fees = accumulatedFees;
        require(fees > 0, "No fees to withdraw");
        accumulatedFees = 0;
        usdc.safeTransfer(treasury, fees);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
