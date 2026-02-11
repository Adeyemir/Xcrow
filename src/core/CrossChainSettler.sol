// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ITokenMessengerV2} from "../interfaces/ICCTPv2.sol";
import {XcrowTypes} from "../libraries/XcrowTypes.sol";

/// @title CrossChainSettler
/// @notice Handles cross-chain USDC settlement via CCTP V2
/// @dev Burns USDC on source chain; Circle mints on destination chain
contract CrossChainSettler is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // --- State ---
    IERC20 public immutable usdc;
    ITokenMessengerV2 public immutable tokenMessenger;
    uint32 public immutable localDomain; // CCTP domain of this chain

    /// @notice Supported destination domains
    mapping(uint32 => bool) public supportedDomains;

    /// @notice Settler contract addresses on destination chains (domain => bytes32 address)
    mapping(uint32 => bytes32) public destinationSettlers;

    /// @notice Authorized callers (e.g., the Router)
    mapping(address => bool) public authorizedCallers;

    /// @notice Cross-chain settlement records
    struct Settlement {
        uint256 jobId;
        uint256 amount;
        uint32 destinationDomain;
        bytes32 mintRecipient;
        uint64 cctpNonce;
        uint256 settledAt;
        bool completed;
    }

    mapping(uint256 => Settlement) public settlements; // jobId => Settlement
    uint256[] public settlementHistory;

    // --- Events ---
    event CrossChainSettlementInitiated(
        uint256 indexed jobId,
        uint32 indexed destinationDomain,
        bytes32 mintRecipient,
        uint256 amount,
        uint64 cctpNonce
    );
    event DomainConfigured(uint32 indexed domain, bool supported, bytes32 settler);

    // --- Constructor ---
    constructor(
        address _usdc,
        address _tokenMessenger,
        uint32 _localDomain
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC");
        require(_tokenMessenger != address(0), "Invalid TokenMessenger");

        usdc = IERC20(_usdc);
        tokenMessenger = ITokenMessengerV2(_tokenMessenger);
        localDomain = _localDomain;
    }

    // --- Core Functions ---

    /// @notice Initiate cross-chain USDC settlement via CCTP V2
    /// @param jobId The Xcrow job ID
    /// @param amount USDC amount to send (already transferred to this contract)
    /// @param destinationDomain CCTP domain of the destination chain
    /// @param mintRecipient Agent's wallet on destination chain (as bytes32)
    /// @param hookData Optional CCTP V2 hook data for post-transfer automation
    /// @return nonce CCTP message nonce for tracking
    function settleCrossChain(
        uint256 jobId,
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        bytes calldata hookData
    ) external nonReentrant whenNotPaused returns (uint64 nonce) {
        require(authorizedCallers[msg.sender] || msg.sender == owner(), "Not authorized");
        require(supportedDomains[destinationDomain], "Unsupported destination");
        require(amount > 0, "Amount must be > 0");
        require(mintRecipient != bytes32(0), "Invalid recipient");
        require(settlements[jobId].settledAt == 0, "Already settled");

        // Approve CCTP TokenMessenger to burn USDC (use forceApprove to handle stale approvals)
        usdc.forceApprove(address(tokenMessenger), amount);

        // Get minimum fee for this transfer
        uint256 minFee = tokenMessenger.getMinFee(amount, destinationDomain);

        // Determine destination caller (0 = permissionless, anyone can relay)
        bytes32 destinationCaller = destinationSettlers[destinationDomain];

        // Burn USDC on source chain via CCTP V2
        nonce = tokenMessenger.depositForBurnWithCaller(
            amount,
            destinationDomain,
            mintRecipient,
            address(usdc),
            destinationCaller,
            minFee,
            hookData
        );

        // Record settlement
        settlements[jobId] = Settlement({
            jobId: jobId,
            amount: amount,
            destinationDomain: destinationDomain,
            mintRecipient: mintRecipient,
            cctpNonce: nonce,
            settledAt: block.timestamp,
            completed: true
        });
        settlementHistory.push(jobId);

        emit CrossChainSettlementInitiated(jobId, destinationDomain, mintRecipient, amount, nonce);
    }

    /// @notice Get the minimum CCTP fee for a transfer
    function getSettlementFee(uint256 amount, uint32 destinationDomain) external view returns (uint256) {
        return tokenMessenger.getMinFee(amount, destinationDomain);
    }

    /// @notice Convert an address to bytes32 for CCTP
    function addressToBytes32(address addr) external pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @notice Convert bytes32 back to address
    function bytes32ToAddress(bytes32 buf) external pure returns (address) {
        return address(uint160(uint256(buf)));
    }

    // --- View Functions ---

    function getSettlement(uint256 jobId) external view returns (Settlement memory) {
        return settlements[jobId];
    }

    function getSettlementCount() external view returns (uint256) {
        return settlementHistory.length;
    }

    // --- Admin Functions ---

    /// @notice Configure a supported destination domain
    function configureDomain(uint32 domain, bool supported, bytes32 settler) external onlyOwner {
        supportedDomains[domain] = supported;
        destinationSettlers[domain] = settler;
        emit DomainConfigured(domain, supported, settler);
    }

    /// @notice Batch configure multiple domains
    function configureDomains(
        uint32[] calldata domains,
        bool[] calldata supported,
        bytes32[] calldata settlers
    ) external onlyOwner {
        require(
            domains.length == supported.length && domains.length == settlers.length,
            "Length mismatch"
        );
        for (uint256 i = 0; i < domains.length; i++) {
            supportedDomains[domains[i]] = supported[i];
            destinationSettlers[domains[i]] = settlers[i];
            emit DomainConfigured(domains[i], supported[i], settlers[i]);
        }
    }

    /// @notice Emergency rescue stuck USDC (only if not part of active settlements)
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Add or remove authorized callers
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
