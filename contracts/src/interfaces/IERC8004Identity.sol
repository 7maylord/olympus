// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC8004Identity {
    event AgentRegistered(
        uint256 indexed tokenId,
        address indexed operator,
        string metadataURI
    );

    function registerAgent(
        string calldata metadataURI
    ) external payable returns (uint256 tokenId);
    function getAgentURI(uint256 tokenId) external view returns (string memory);
    function agentOf(address operator) external view returns (uint256 tokenId);
}
