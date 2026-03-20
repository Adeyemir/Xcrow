// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {XcrowTypes} from "../libraries/XcrowTypes.sol";
import {XcrowEscrow} from "./XcrowEscrow.sol";
import {ReputationPricer} from "./ReputationPricer.sol";
import {CrossChainSettler} from "./CrossChainSettler.sol";
import {IERC8004Identity} from "../interfaces/IERC8004Identity.sol";
import {IERC8004Reputation} from "../interfaces/IERC8004Reputation.sol";

/// @title XcrowRouter
/// @notice Single entry point for Xcrow protocol interactions
/// @dev Orchestrates escrow, pricing, and cross-chain settlement
contract XcrowRouter is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // --- State ---
    IERC20 public immutable usdc;
    XcrowEscrow public escrow;
    ReputationPricer public pricer;
    CrossChainSettler public settler;
    IERC8004Identity public immutable identityRegistry;
    IERC8004Reputation public immutable reputationRegistry;

    uint32 public immutable localChainId;

    /// @notice Maps escrow jobId to the original client who hired via the Router
    mapping(uint256 => address) public originalClient;

    /// @notice Maps escrow jobId to the ERC-8004 agentId for reputation feedback
    mapping(uint256 => uint256) public jobERC8004AgentId;

    // --- Events ---
    event AgentHired(
        uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount, bool crossChain
    );
    event CrossChainSettled(uint256 indexed jobId, uint32 destinationDomain, uint64 cctpNonce);
    event FeedbackSubmitted(uint256 indexed jobId, uint256 indexed agentId, int128 value);

    // --- Constructor ---
    constructor(
        address _usdc,
        address _escrow,
        address _pricer,
        address _settler,
        address _identityRegistry,
        address _reputationRegistry,
        uint32 _localChainId
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC");

        usdc = IERC20(_usdc);
        escrow = XcrowEscrow(_escrow);
        pricer = ReputationPricer(_pricer);
        settler = CrossChainSettler(_settler);
        identityRegistry = IERC8004Identity(_identityRegistry);
        reputationRegistry = IERC8004Reputation(_reputationRegistry);
        localChainId = _localChainId;
    }

    // --- Core Functions ---

    /// @notice Hire an agent by wallet address with EIP-2612 permit — no ERC-8004 ID needed
    /// @param erc8004AgentId The agent's ERC-8004 token ID for reputation tracking (0 if unknown)
    function hireAgentByWalletWithPermit(
        address agentWallet,
        uint256 amount,
        bytes32 taskHash,
        uint256 deadline,
        uint256 erc8004AgentId,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused returns (uint256 jobId) {
        IERC20Permit(address(usdc)).permit(msg.sender, address(this), amount, permitDeadline, v, r, s);
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.forceApprove(address(escrow), amount);

        jobId = escrow.createJobByWallet(agentWallet, amount, taskHash, deadline);
        originalClient[jobId] = msg.sender;
        if (erc8004AgentId != 0) jobERC8004AgentId[jobId] = erc8004AgentId;

        emit AgentHired(jobId, erc8004AgentId, msg.sender, amount, false);
    }

    /// @notice Hire an agent on the same chain
    /// @param agentId ERC-8004 agent ID
    /// @param amount USDC amount to pay
    /// @param taskHash keccak256 of task description
    /// @param deadline Block timestamp deadline
    /// @return jobId The created job ID
    function hireAgent(uint256 agentId, uint256 amount, bytes32 taskHash, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 jobId)
    {
        // Transfer USDC from client to this router, then approve escrow
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.forceApprove(address(escrow), amount);

        // Create job in escrow
        jobId = escrow.createJob(agentId, localChainId, amount, taskHash, deadline);

        // Track original client for delegation
        originalClient[jobId] = msg.sender;

        emit AgentHired(jobId, agentId, msg.sender, amount, false);
    }

    /// @notice Hire an agent using EIP-2612 permit — one tx, no pre-approval needed
    /// @param agentId ERC-8004 agent ID
    /// @param amount USDC amount to pay
    /// @param taskHash keccak256 of task description
    /// @param deadline Job deadline (block timestamp)
    /// @param permitDeadline Permit expiry (block timestamp)
    /// @param v Permit signature v
    /// @param r Permit signature r
    /// @param s Permit signature s
    /// @return jobId The created job ID
    function hireAgentWithPermit(
        uint256 agentId,
        uint256 amount,
        bytes32 taskHash,
        uint256 deadline,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused returns (uint256 jobId) {
        // Execute permit — approves this router in the same tx
        IERC20Permit(address(usdc)).permit(msg.sender, address(this), amount, permitDeadline, v, r, s);

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.forceApprove(address(escrow), amount);

        jobId = escrow.createJob(agentId, localChainId, amount, taskHash, deadline);
        originalClient[jobId] = msg.sender;

        emit AgentHired(jobId, agentId, msg.sender, amount, false);
    }

    /// @notice Hire an agent and get a reputation-weighted quote first
    /// @param agentId ERC-8004 agent ID
    /// @param taskHash keccak256 of task description
    /// @param deadline Block timestamp deadline
    /// @return jobId The created job ID
    /// @return quote The price quote used
    function hireAgentWithQuote(uint256 agentId, bytes32 taskHash, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 jobId, XcrowTypes.PriceQuote memory quote)
    {
        // Get reputation-weighted quote
        quote = pricer.getQuote(agentId, escrow.protocolFeeBps());

        // Only pull effectiveRate — escrow calculates its own platformFee internally
        usdc.safeTransferFrom(msg.sender, address(this), quote.effectiveRate);
        usdc.forceApprove(address(escrow), quote.effectiveRate);

        // Create job with the quoted effective rate — escrow adds its own fee calculation
        jobId = escrow.createJob(agentId, localChainId, quote.effectiveRate, taskHash, deadline);

        // Track original client for delegation
        originalClient[jobId] = msg.sender;

        emit AgentHired(jobId, agentId, msg.sender, quote.effectiveRate, false);
    }

    /// @notice Hire an agent for a cross-chain job (payment bridged via CCTP V2)
    /// @param agentId ERC-8004 agent ID
    /// @param amount USDC amount to pay
    /// @param taskHash keccak256 of task description
    /// @param deadline Block timestamp deadline
    /// @param destinationDomain CCTP destination domain for agent payout
    /// @return jobId The created job ID
    function hireAgentCrossChain(
        uint256 agentId,
        uint256 amount,
        bytes32 taskHash,
        uint256 deadline,
        uint32 destinationDomain
    ) external nonReentrant whenNotPaused returns (uint256 jobId) {
        // Transfer USDC from client to router, then approve escrow
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.forceApprove(address(escrow), amount);

        // Create cross-chain job in escrow
        jobId = escrow.createCrossChainJob(agentId, localChainId, amount, taskHash, deadline, destinationDomain);

        // Track original client for delegation
        originalClient[jobId] = msg.sender;

        emit AgentHired(jobId, agentId, msg.sender, amount, true);
    }

    /// @notice Settle a completed job — handles same-chain or cross-chain
    /// @param jobId Job to settle
    /// @param destinationDomain CCTP domain (0 for same-chain settlement)
    /// @param hookData Optional CCTP V2 hook data
    function settleAndPay(uint256 jobId, uint32 destinationDomain, bytes calldata hookData)
        external
        nonReentrant
        whenNotPaused
    {
        // Use originalClient for jobs created via router, fall back to job.client for direct escrow jobs
        address jobClient = originalClient[jobId];
        if (jobClient == address(0)) {
            jobClient = escrow.getJob(jobId).client;
        }
        require(msg.sender == jobClient, "Only client can settle");

        XcrowTypes.Job memory job = escrow.getJob(jobId);
        require(job.status == XcrowTypes.JobStatus.Completed, "Job not completed");

        if (destinationDomain == 0 || !job.isCrossChain) {
            // Same-chain settlement — settle via escrow
            escrow.settleJob(jobId);

            // Auto-submit proof-of-payment feedback to ERC-8004
            // Use jobERC8004AgentId if set (wallet-based hires), else fall back to job.agentId
            uint256 reputationAgentId = jobERC8004AgentId[jobId] != 0 ? jobERC8004AgentId[jobId] : job.agentId;
            // try/catch so a reputation registry failure never blocks settlement
            if (reputationAgentId != 0) {
                try reputationRegistry.giveFeedback(
                    reputationAgentId,
                    1, // positive value: payment was made
                    0, // valueDecimals
                    "", // tag1
                    "", // tag2
                    "", // endpoint
                    "", // feedbackURI
                    keccak256(abi.encode(jobClient, job.agentWallet, block.chainid, jobId))
                ) {
                    emit FeedbackSubmitted(jobId, reputationAgentId, 1);
                } catch {}
            }
        } else {
            // Cross-chain settlement via CCTP V2
            // First settle in escrow — this pays the agent on this chain.
            // For cross-chain, the escrow's agentWallet should be set to this router
            // so we can bridge the funds. The router then bridges to the real agent.
            escrow.settleJob(jobId);

            uint256 agentPayout = job.amount - job.platformFee;

            // Transfer USDC to settler for cross-chain bridging
            usdc.safeTransfer(address(settler), agentPayout);

            // Convert agent wallet to bytes32 for CCTP
            bytes32 mintRecipient = bytes32(uint256(uint160(job.agentWallet)));

            // Initiate cross-chain settlement
            uint64 nonce = settler.settleCrossChain(jobId, agentPayout, destinationDomain, mintRecipient, hookData);

            emit CrossChainSettled(jobId, destinationDomain, nonce);
        }
    }

    /// @notice Cancel a Router-created job on behalf of the original client
    /// @param jobId Job to cancel (must be in Created status)
    function cancelJobViaRouter(uint256 jobId) external nonReentrant whenNotPaused {
        address jobClient = originalClient[jobId];
        require(jobClient != address(0), "Not a router job");
        require(msg.sender == jobClient, "Only original client can cancel");

        escrow.cancelJob(jobId);

        // Forward the refunded USDC from router back to original client
        XcrowTypes.Job memory job = escrow.getJob(jobId);
        uint256 routerBalance = usdc.balanceOf(address(this));
        if (routerBalance >= job.amount) {
            usdc.safeTransfer(jobClient, job.amount);
        }
    }

    /// @notice Agent rejects a Router-created job — USDC refunded directly to original client
    /// @param jobId Job to reject (must be in Created status)
    function rejectJobViaRouter(uint256 jobId) external nonReentrant whenNotPaused {
        XcrowTypes.Job memory job = escrow.getJob(jobId);
        require(msg.sender == job.agentWallet, "Not agent wallet");

        address refundRecipient = originalClient[jobId];
        if (refundRecipient == address(0)) refundRecipient = job.client;

        escrow.rejectJob(jobId, refundRecipient);
    }

    /// @notice Dispute a Router-created job on behalf of the original client
    /// @param jobId Job to dispute
    /// @param reason Human-readable reason for the dispute
    function disputeJobViaRouter(uint256 jobId, string calldata reason) external nonReentrant whenNotPaused {
        address jobClient = originalClient[jobId];
        require(jobClient != address(0), "Not a router job");
        require(msg.sender == jobClient, "Only original client can dispute");

        escrow.disputeJob(jobId, reason);
    }

    /// @notice Submit feedback to ERC-8004 with proof of payment
    /// @param jobId Settled job to leave feedback for
    /// @param value Feedback value (e.g., 0-100)
    /// @param valueDecimals Decimals for the value
    /// @param tag1 Optional tag (e.g., "quality", "speed")
    /// @param feedbackURI URI to off-chain feedback file (with proofOfPayment)
    /// @param feedbackHash keccak256 of feedback file
    function submitFeedback(
        uint256 jobId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external nonReentrant {
        // Use originalClient for jobs created via router, fall back to job.client
        address jobClient = originalClient[jobId];
        XcrowTypes.Job memory job = escrow.getJob(jobId);
        if (jobClient == address(0)) {
            jobClient = job.client;
        }
        require(msg.sender == jobClient, "Only client can submit feedback");
        require(job.status == XcrowTypes.JobStatus.Settled, "Job not settled");

        // Use jobERC8004AgentId for wallet-based hires (job.agentId = 0 for those)
        uint256 reputationAgentId = jobERC8004AgentId[jobId] != 0 ? jobERC8004AgentId[jobId] : job.agentId;
        require(reputationAgentId != 0, "No ERC-8004 agent id linked to job");

        // Submit feedback to ERC-8004 Reputation Registry
        reputationRegistry.giveFeedback(
            reputationAgentId,
            value,
            valueDecimals,
            tag1,
            "xcrow", // tag2 = protocol identifier
            "", // endpoint
            feedbackURI,
            feedbackHash
        );

        emit FeedbackSubmitted(jobId, reputationAgentId, value);
    }

    // --- View Functions ---

    /// @notice Get a reputation-weighted price quote
    function getQuote(uint256 agentId) external view returns (XcrowTypes.PriceQuote memory) {
        return pricer.getQuote(agentId, escrow.protocolFeeBps());
    }

    /// @notice Get agent info from ERC-8004
    function getAgentInfo(uint256 agentId) external view returns (address owner, address wallet, string memory uri) {
        owner = identityRegistry.ownerOf(agentId);
        wallet = identityRegistry.getAgentWallet(agentId);
        uri = identityRegistry.tokenURI(agentId);
    }

    /// @notice Estimate cross-chain settlement fee
    function estimateCrossChainFee(uint256 amount, uint32 destinationDomain) external view returns (uint256) {
        return settler.getSettlementFee(amount, destinationDomain);
    }

    // --- Admin Functions ---

    function updateEscrow(address newEscrow) external onlyOwner {
        escrow = XcrowEscrow(newEscrow);
    }

    function updatePricer(address newPricer) external onlyOwner {
        pricer = ReputationPricer(newPricer);
    }

    function updateSettler(address newSettler) external onlyOwner {
        settler = CrossChainSettler(newSettler);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
