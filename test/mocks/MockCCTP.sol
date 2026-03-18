// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITokenMessengerV2, IMessageTransmitterV2} from "../../src/interfaces/ICCTPv2.sol";

/// @notice Mock CCTP V2 TokenMessenger for testing
contract MockTokenMessenger is ITokenMessengerV2 {
    uint64 private _nonce;
    uint256 public constant MOCK_MIN_FEE = 1000; // 0.001 USDC

    struct BurnRecord {
        uint256 amount;
        uint32 destinationDomain;
        bytes32 mintRecipient;
        address burnToken;
        bytes32 destinationCaller;
        uint256 maxFee;
        bytes hookData;
    }

    BurnRecord[] public burnRecords;

    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        bytes calldata hookData
    ) external returns (uint64 nonce) {
        // Pull tokens from caller (simulates burn)
        IERC20(burnToken).transferFrom(msg.sender, address(this), amount);

        burnRecords.push(
            BurnRecord({
                amount: amount,
                destinationDomain: destinationDomain,
                mintRecipient: mintRecipient,
                burnToken: burnToken,
                destinationCaller: destinationCaller,
                maxFee: maxFee,
                hookData: hookData
            })
        );

        nonce = _nonce++;
    }

    function getMinFee(uint256, uint32) external pure returns (uint256) {
        return MOCK_MIN_FEE;
    }

    // --- Test helpers ---

    function getBurnCount() external view returns (uint256) {
        return burnRecords.length;
    }

    function getLastBurn() external view returns (BurnRecord memory) {
        require(burnRecords.length > 0, "No burns");
        return burnRecords[burnRecords.length - 1];
    }
}

/// @notice Mock CCTP V2 MessageTransmitter for testing
contract MockMessageTransmitter is IMessageTransmitterV2 {
    function receiveMessage(bytes calldata, bytes calldata) external pure returns (bool) {
        return true;
    }
}
