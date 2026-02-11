// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IERC8004Reputation {
    function getIdentityRegistry() external view returns (address);
    function giveFeedback(uint256 agentId, int128 value, uint8 valueDecimals, string calldata tag1, string calldata tag2, string calldata endpoint, string calldata feedbackURI, bytes32 feedbackHash) external;
    function getSummary(uint256 agentId, address[] calldata clientAddresses, string calldata tag1, string calldata tag2) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals);
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex) external view returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked);
    function getClients(uint256 agentId) external view returns (address[] memory);
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64);
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external;
    function appendResponse(uint256 agentId, address clientAddress, uint64 feedbackIndex, string calldata responseURI, bytes32 responseHash) external;

    event NewFeedback(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex, int128 value, uint8 valueDecimals, string indexed indexedTag1, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash);
    event FeedbackRevoked(uint256 indexed agentId, address indexed clientAddress, uint64 indexed feedbackIndex);
}
