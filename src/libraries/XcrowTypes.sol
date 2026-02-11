// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

library XcrowTypes {
    enum JobStatus {
        Created,
        Accepted,
        InProgress,
        Completed,
        Settled,
        Disputed,
        Cancelled,
        Refunded,
        Expired
    }

    struct Job {
        uint256 jobId;
        uint256 agentId;
        uint32 agentChainId;
        address client;
        address agentWallet;
        uint256 amount;
        uint256 platformFee;
        bytes32 taskHash;
        uint256 deadline;
        uint256 createdAt;
        uint256 settledAt;
        JobStatus status;
        bool isCrossChain;
        uint32 destinationDomain;
    }

    struct PriceQuote {
        uint256 agentId;
        uint256 baseRate;
        uint256 effectiveRate;
        uint256 reputationScore;
        uint256 multiplier;
        uint256 platformFee;
        uint256 totalCost;
        uint256 quotedAt;
    }

    struct ChainConfig {
        address usdc;
        address tokenMessenger;
        address messageTransmitter;
        address identityRegistry;
        address reputationRegistry;
        uint32 cctpDomain;
        bool active;
    }
}
