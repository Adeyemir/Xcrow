// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IERC8004Identity {
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    function register(string calldata agentURI) external returns (uint256 agentId);
    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);
    function register() external returns (uint256 agentId);
    function ownerOf(uint256 agentId) external view returns (address);
    function getAgentWallet(uint256 agentId) external view returns (address);
    function tokenURI(uint256 agentId) external view returns (string memory);
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);
    function setAgentURI(uint256 agentId, string calldata newURI) external;
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external;

    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue);
}
