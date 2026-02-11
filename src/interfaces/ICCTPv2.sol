// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface ITokenMessengerV2 {
    function depositForBurnWithCaller(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken, bytes32 destinationCaller, uint256 maxFee, bytes calldata hookData) external returns (uint64 nonce);
    function getMinFee(uint256 amount, uint32 destinationDomain) external view returns (uint256 minFee);
}

interface IMessageTransmitterV2 {
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);
}
