// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IERC8004Identity} from "../../src/interfaces/IERC8004Identity.sol";

/// @notice Mock ERC-8004 Identity Registry for testing
contract MockIdentityRegistry is IERC8004Identity {
    uint256 private _nextAgentId = 1;

    mapping(uint256 => address) public owners;
    mapping(uint256 => address) public agentWallets;
    mapping(uint256 => string) public agentURIs;

    function register(string calldata agentURI) external returns (uint256 agentId) {
        agentId = _nextAgentId++;
        owners[agentId] = msg.sender;
        agentWallets[agentId] = msg.sender;
        agentURIs[agentId] = agentURI;
        emit Registered(agentId, agentURI, msg.sender);
    }

    function register(string calldata, MetadataEntry[] calldata) external returns (uint256) {
        revert("Use simple register");
    }

    function register() external returns (uint256) {
        uint256 agentId = _nextAgentId++;
        owners[agentId] = msg.sender;
        agentWallets[agentId] = msg.sender;
        emit Registered(agentId, "", msg.sender);
        return agentId;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        require(owners[agentId] != address(0), "Agent does not exist");
        return owners[agentId];
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        return agentWallets[agentId];
    }

    function tokenURI(uint256 agentId) external view returns (string memory) {
        return agentURIs[agentId];
    }

    function getMetadata(uint256, string memory) external pure returns (bytes memory) {
        return "";
    }

    function setAgentURI(uint256 agentId, string calldata newURI) external {
        require(owners[agentId] == msg.sender, "Not owner");
        agentURIs[agentId] = newURI;
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    function setAgentWallet(uint256, address, uint256, bytes calldata) external pure {
        revert("Use mock setter");
    }

    // --- Test helpers ---

    function mockSetAgentWallet(uint256 agentId, address wallet) external {
        agentWallets[agentId] = wallet;
    }

    function mockRegisterAgent(address owner, address wallet, string calldata uri) external returns (uint256) {
        uint256 agentId = _nextAgentId++;
        owners[agentId] = owner;
        agentWallets[agentId] = wallet;
        agentURIs[agentId] = uri;
        emit Registered(agentId, uri, owner);
        return agentId;
    }
}
