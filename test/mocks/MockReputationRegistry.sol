// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IERC8004Reputation} from "../../src/interfaces/IERC8004Reputation.sol";

/// @notice Mock ERC-8004 Reputation Registry for testing
contract MockReputationRegistry is IERC8004Reputation {
    address public identityRegistry;

    struct FeedbackEntry {
        int128 value;
        uint8 valueDecimals;
        string tag1;
        string tag2;
        bool isRevoked;
    }

    // agentId => clientAddress => feedbackIndex => FeedbackEntry
    mapping(uint256 => mapping(address => mapping(uint64 => FeedbackEntry))) public feedbacks;
    mapping(uint256 => mapping(address => uint64)) public lastIndexes;
    mapping(uint256 => address[]) public agentClients;

    // Mock summary values (agentId => values)
    mapping(uint256 => int128) public mockSummaryValue;
    mapping(uint256 => uint8) public mockSummaryDecimals;
    mapping(uint256 => uint64) public mockSummaryCount;

    constructor(address _identityRegistry) {
        identityRegistry = _identityRegistry;
    }

    function getIdentityRegistry() external view returns (address) {
        return identityRegistry;
    }

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external {
        uint64 idx = lastIndexes[agentId][msg.sender] + 1;
        lastIndexes[agentId][msg.sender] = idx;

        feedbacks[agentId][msg.sender][idx] =
            FeedbackEntry({value: value, valueDecimals: valueDecimals, tag1: tag1, tag2: tag2, isRevoked: false});

        // Track client
        if (idx == 1) {
            agentClients[agentId].push(msg.sender);
        }

        emit NewFeedback(
            agentId, msg.sender, idx, value, valueDecimals, tag1, tag1, tag2, endpoint, feedbackURI, feedbackHash
        );
    }

    function getSummary(uint256 agentId, address[] calldata, string calldata, string calldata)
        external
        view
        returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals)
    {
        return (mockSummaryCount[agentId], mockSummaryValue[agentId], mockSummaryDecimals[agentId]);
    }

    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked)
    {
        FeedbackEntry storage f = feedbacks[agentId][clientAddress][feedbackIndex];
        return (f.value, f.valueDecimals, f.tag1, f.tag2, f.isRevoked);
    }

    function getClients(uint256 agentId) external view returns (address[] memory) {
        return agentClients[agentId];
    }

    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64) {
        return lastIndexes[agentId][clientAddress];
    }

    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external {
        feedbacks[agentId][msg.sender][feedbackIndex].isRevoked = true;
        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    function appendResponse(uint256, address, uint64, string calldata, bytes32) external pure {}

    // --- Test helpers ---

    function mockSetSummary(uint256 agentId, uint64 count, int128 value, uint8 decimals) external {
        mockSummaryCount[agentId] = count;
        mockSummaryValue[agentId] = value;
        mockSummaryDecimals[agentId] = decimals;
    }
}
