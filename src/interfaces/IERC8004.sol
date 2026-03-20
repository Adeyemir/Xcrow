// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title IERC8004
/// @notice Combined ERC-8004 interface: Identity + Reputation registries
/// @dev Import this file to get both registries in one place

// ---------------------------------------------------------------------------
// Identity Registry
// ---------------------------------------------------------------------------

interface IERC8004Identity {
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    /// @notice Register a new agent NFT
    function register(string calldata agentURI) external returns (uint256 agentId);
    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);
    function register() external returns (uint256 agentId);

    /// @notice Returns the address that owns the agent NFT (controls identity)
    function ownerOf(uint256 agentId) external view returns (address);

    /// @notice Returns the agent's designated payment / operating wallet
    /// @dev May differ from ownerOf — used for payment routing
    function getAgentWallet(uint256 agentId) external view returns (address);

    function tokenURI(uint256 agentId) external view returns (string memory);
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);
    function setAgentURI(uint256 agentId, string calldata newURI) external;
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external;

    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(
        uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue
    );
}

// ---------------------------------------------------------------------------
// Reputation Registry
// ---------------------------------------------------------------------------

interface IERC8004Reputation {
    function getIdentityRegistry() external view returns (address);

    /// @notice Submit feedback for an agent after a completed interaction
    /// @param agentId     ERC-8004 agent token ID
    /// @param value       Feedback value (positive or negative, scaled by valueDecimals)
    /// @param valueDecimals Decimal places for value
    /// @param tag1        Primary tag (e.g. "quality", "xcrow")
    /// @param tag2        Secondary tag (e.g. "payment", "speed")
    /// @param endpoint    Optional agent endpoint string
    /// @param feedbackURI URI to off-chain feedback file (may include proofOfPayment)
    /// @param feedbackHash keccak256 of the feedback file for integrity
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;

    /// @notice Aggregate reputation across a set of reviewers and optional tags
    /// @param agentId         ERC-8004 agent token ID
    /// @param clientAddresses Addresses to include (trusted reviewer filter)
    /// @param tag1            Filter by primary tag (empty = all)
    /// @param tag2            Filter by secondary tag (empty = all)
    /// @return count               Number of matching feedback entries
    /// @return summaryValue        Aggregated value
    /// @return summaryValueDecimals Decimals of the aggregated value
    function getSummary(uint256 agentId, address[] calldata clientAddresses, string calldata tag1, string calldata tag2)
        external
        view
        returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals);

    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked);

    function getClients(uint256 agentId) external view returns (address[] memory);
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64);
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external;
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external;

    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        int128 value,
        uint8 valueDecimals,
        string indexed indexedTag1,
        string tag1,
        string tag2,
        string endpoint,
        string feedbackURI,
        bytes32 feedbackHash
    );
    event FeedbackRevoked(uint256 indexed agentId, address indexed clientAddress, uint64 indexed feedbackIndex);
}
