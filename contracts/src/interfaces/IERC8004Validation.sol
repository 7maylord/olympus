// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC8004Validation {
    event ValidationRequested(bytes32 indexed requestId, uint256 agentId, bytes32 taskId);
    event ValidationRecorded(bytes32 indexed requestId, bool valid);

    function requestValidation(uint256 agentId, bytes32 taskId, bytes calldata proof)
        external
        returns (bytes32 requestId);

    function recordValidation(bytes32 requestId, bool valid, bytes calldata attestation) external;
}
