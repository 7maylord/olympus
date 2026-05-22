// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC8004Reputation {
    event FeedbackPosted(uint256 indexed agentId, bool success, uint256 score);

    function postFeedback(uint256 agentId, bool success, uint256 latencyMs, bytes calldata data) external;
    function getFeedback(uint256 agentId) external view returns (uint256 score, uint256 totalInteractions);
}
