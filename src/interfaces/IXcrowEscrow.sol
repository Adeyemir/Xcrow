// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../libraries/XcrowTypes.sol";

interface IXcrowEscrow {
    function createJob(uint256 agentId, uint32 agentChainId, uint256 amount, bytes32 taskHash, uint256 deadline)
        external
        returns (uint256 jobId);
    function acceptJob(uint256 jobId) external;
    function startJob(uint256 jobId) external;
    function completeJob(uint256 jobId) external;
    function settleJob(uint256 jobId) external;
    function disputeJob(uint256 jobId, string calldata reason) external;
    function cancelJob(uint256 jobId) external;
    function refundExpiredJob(uint256 jobId) external;
    function getJob(uint256 jobId) external view returns (XcrowTypes.Job memory);
    function getClientJobs(address client) external view returns (uint256[] memory);
    function getAgentJobs(uint256 agentId) external view returns (uint256[] memory);

    event JobCreated(uint256 indexed jobId, uint256 indexed agentId, address indexed client, uint256 amount);
    event JobAccepted(uint256 indexed jobId, uint256 indexed agentId);
    event JobStarted(uint256 indexed jobId);
    event JobCompleted(uint256 indexed jobId);
    event JobSettled(uint256 indexed jobId, uint256 agentPayout, uint256 protocolFee);
    event JobDisputed(uint256 indexed jobId, address indexed disputedBy, string reason);
    event JobCancelled(uint256 indexed jobId);
    event JobRefunded(uint256 indexed jobId, uint256 refundAmount);
}
