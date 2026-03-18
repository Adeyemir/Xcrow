// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC8004Reputation} from "../interfaces/IERC8004Reputation.sol";
import {IERC8004Identity} from "../interfaces/IERC8004Identity.sol";
import {XcrowTypes} from "../libraries/XcrowTypes.sol";

/// @title ReputationPricer
/// @notice Dynamic pricing based on ERC-8004 reputation scores
/// @dev Reads reputation from ERC-8004 and computes reputation-weighted pricing
contract ReputationPricer is Ownable {
    // --- State ---
    IERC8004Reputation public immutable reputationRegistry;
    IERC8004Identity public immutable identityRegistry;

    /// @notice Maximum reputation premium as basis points (20000 = 2x)
    uint256 public maxPremiumBps;

    /// @notice Maximum expected reputation score (for normalization)
    uint256 public maxReputationScore;

    /// @notice Minimum number of reviews required for premium pricing
    uint64 public minReviewCount;

    /// @notice Agent base rates (agentId => baseRate in USDC, 6 decimals)
    mapping(uint256 => uint256) public agentBaseRates;

    /// @notice Trusted reviewers for Sybil-resistant scoring
    address[] public trustedReviewers;
    mapping(address => bool) public isTrustedReviewer;

    /// @notice Reputation tag used for pricing queries
    string public pricingTag;

    // --- Events ---
    event BaseRateSet(uint256 indexed agentId, uint256 baseRate);
    event TrustedReviewerAdded(address indexed reviewer);
    event TrustedReviewerRemoved(address indexed reviewer);
    event PricingConfigUpdated(uint256 maxPremiumBps, uint256 maxReputationScore, uint64 minReviewCount);

    // --- Constructor ---
    constructor(
        address _reputationRegistry,
        address _identityRegistry,
        uint256 _maxPremiumBps,
        uint256 _maxReputationScore,
        uint64 _minReviewCount,
        string memory _pricingTag
    ) Ownable(msg.sender) {
        require(_reputationRegistry != address(0), "Invalid reputation registry");
        require(_identityRegistry != address(0), "Invalid identity registry");
        require(_maxPremiumBps > 0, "Premium must be > 0");
        require(_maxReputationScore > 0, "Max score must be > 0");

        reputationRegistry = IERC8004Reputation(_reputationRegistry);
        identityRegistry = IERC8004Identity(_identityRegistry);
        maxPremiumBps = _maxPremiumBps;
        maxReputationScore = _maxReputationScore;
        minReviewCount = _minReviewCount;
        pricingTag = _pricingTag;
    }

    // --- Agent Rate Management ---

    /// @notice Agent sets their own base rate
    /// @param agentId ERC-8004 agent ID
    /// @param baseRate Base rate in USDC (6 decimals)
    function setBaseRate(uint256 agentId, uint256 baseRate) external {
        require(baseRate > 0, "Rate must be > 0");
        // Verify caller owns or operates the agent
        address agentOwner = identityRegistry.ownerOf(agentId);
        address agentWallet = identityRegistry.getAgentWallet(agentId);
        require(msg.sender == agentOwner || msg.sender == agentWallet, "Not agent owner or wallet");

        agentBaseRates[agentId] = baseRate;
        emit BaseRateSet(agentId, baseRate);
    }

    // --- Pricing Functions ---

    /// @notice Get a full price quote for hiring an agent
    /// @param agentId ERC-8004 agent ID
    /// @param protocolFeeBps Protocol fee in basis points
    /// @return quote Full price quote with breakdown
    function getQuote(uint256 agentId, uint256 protocolFeeBps)
        external
        view
        returns (XcrowTypes.PriceQuote memory quote)
    {
        uint256 baseRate = agentBaseRates[agentId];
        require(baseRate > 0, "Agent has no base rate");

        (uint256 reputationScore, uint256 multiplierBps) = _getReputationMultiplier(agentId);
        uint256 effectiveRate = (baseRate * multiplierBps) / 10000;
        uint256 platformFee = (effectiveRate * protocolFeeBps) / 10000;

        quote = XcrowTypes.PriceQuote({
            agentId: agentId,
            baseRate: baseRate,
            effectiveRate: effectiveRate,
            reputationScore: reputationScore,
            multiplier: multiplierBps,
            platformFee: platformFee,
            totalCost: effectiveRate + platformFee,
            quotedAt: block.timestamp
        });
    }

    /// @notice Get just the reputation multiplier for an agent
    /// @param agentId ERC-8004 agent ID
    /// @return score Normalized reputation score
    /// @return multiplierBps Multiplier in basis points (10000 = 1x, 30000 = 3x)
    function getReputationMultiplier(uint256 agentId) external view returns (uint256 score, uint256 multiplierBps) {
        return _getReputationMultiplier(agentId);
    }

    // --- Internal ---

    function _getReputationMultiplier(uint256 agentId) internal view returns (uint256 score, uint256 multiplierBps) {
        // If no trusted reviewers set, return base multiplier (1x)
        if (trustedReviewers.length == 0) {
            return (0, 10000);
        }

        // Query ERC-8004 reputation with trusted reviewers filter
        (uint64 count, int128 summaryValue, uint8 summaryValueDecimals) =
            reputationRegistry.getSummary(
                agentId,
                trustedReviewers,
                pricingTag,
                "" // no tag2 filter
            );

        // Not enough reviews — return base rate
        if (count < minReviewCount) {
            return (0, 10000);
        }

        // Handle negative reputation — apply penalty below 1x
        if (summaryValue < 0) {
            uint256 rawNegative = uint256(uint128(-summaryValue));
            if (summaryValueDecimals > 0) {
                rawNegative = rawNegative / (10 ** summaryValueDecimals);
            }
            if (rawNegative > maxReputationScore) {
                rawNegative = maxReputationScore;
            }
            // Penalty: multiplier = 10000 - (rawNegative * maxPenaltyBps) / maxReputationScore
            // Cap at minimum 1000 bps (0.1x) to avoid zero/negative multiplier
            uint256 penalty = (rawNegative * maxPremiumBps) / maxReputationScore;
            if (penalty >= 9000) {
                multiplierBps = 1000; // Floor at 0.1x
            } else {
                multiplierBps = 10000 - penalty;
            }
            score = 0;
            return (score, multiplierBps);
        }

        // Positive reputation — apply premium above 1x
        uint256 rawScore;
        if (summaryValue > 0) {
            rawScore = uint256(uint128(summaryValue));
            // Adjust for decimals
            if (summaryValueDecimals > 0) {
                rawScore = rawScore / (10 ** summaryValueDecimals);
            }
        }

        // Cap at max
        if (rawScore > maxReputationScore) {
            rawScore = maxReputationScore;
        }

        // Calculate multiplier:
        // multiplier = 10000 + (rawScore / maxReputationScore) * maxPremiumBps
        // Using integer math: multiplier = 10000 + (rawScore * maxPremiumBps) / maxReputationScore
        multiplierBps = 10000 + (rawScore * maxPremiumBps) / maxReputationScore;
        score = rawScore;
    }

    // --- Admin Functions ---

    function addTrustedReviewer(address reviewer) external onlyOwner {
        require(!isTrustedReviewer[reviewer], "Already trusted");
        trustedReviewers.push(reviewer);
        isTrustedReviewer[reviewer] = true;
        emit TrustedReviewerAdded(reviewer);
    }

    function removeTrustedReviewer(address reviewer) external onlyOwner {
        require(isTrustedReviewer[reviewer], "Not trusted");
        isTrustedReviewer[reviewer] = false;

        // Remove from array
        for (uint256 i = 0; i < trustedReviewers.length; i++) {
            if (trustedReviewers[i] == reviewer) {
                trustedReviewers[i] = trustedReviewers[trustedReviewers.length - 1];
                trustedReviewers.pop();
                break;
            }
        }
        emit TrustedReviewerRemoved(reviewer);
    }

    function updatePricingConfig(uint256 _maxPremiumBps, uint256 _maxReputationScore, uint64 _minReviewCount)
        external
        onlyOwner
    {
        require(_maxPremiumBps > 0, "Premium must be > 0");
        require(_maxReputationScore > 0, "Max score must be > 0");
        maxPremiumBps = _maxPremiumBps;
        maxReputationScore = _maxReputationScore;
        minReviewCount = _minReviewCount;
        emit PricingConfigUpdated(_maxPremiumBps, _maxReputationScore, _minReviewCount);
    }

    function setPricingTag(string calldata _tag) external onlyOwner {
        pricingTag = _tag;
    }

    function getTrustedReviewers() external view returns (address[] memory) {
        return trustedReviewers;
    }
}
