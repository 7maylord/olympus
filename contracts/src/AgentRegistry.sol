// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IERC8004Identity.sol";
import "./interfaces/IERC8004Reputation.sol";
import "./interfaces/IERC8004Validation.sol";

contract AgentRegistry is ERC721URIStorage, ReentrancyGuard, IERC8004Identity, IERC8004Reputation, IERC8004Validation {

    uint256 public constant MIN_STAKE = 0.01 ether;
    uint256 public constant CLAIM_BOND = 0.0001 ether;
    uint256 public constant STAKE_PER_CLAIM_SLOT = 0.005 ether;
    uint256 public constant INITIAL_REPUTATION = 500;
    uint256 public constant MAX_REPUTATION = 1000;
    uint256 public constant MISS_SLASH_BPS = 1000;
    uint256 public constant MISS_WINDOW = 24 hours;

    struct AgentData {
        address operator;
        bytes32[] capabilities;
        uint256 stake;
        uint256 reputationScore;
        uint256 tasksCompleted;
        uint256 tasksFailed;
        uint256 claimBondsForfeited;
        uint256 missCount;
        uint256 firstMissAt;
        bool active;
    }

    uint256 private _tokenIdCounter;

    mapping(uint256 => AgentData) public agentData;
    mapping(address => uint256) public operatorToId;

    address public verifier;
    address public treasury;

    error InsufficientStake();
    error AlreadyRegistered();
    error NotActive();
    error NotVerifier();
    error AgentNotFound();
    error WithdrawFailed();

    modifier onlyVerifier() {
        if (msg.sender != verifier) revert NotVerifier();
        _;
    }

    modifier agentExists(uint256 agentId) {
        if (agentData[agentId].operator == address(0)) revert AgentNotFound();
        _;
    }

    constructor(address _treasury) ERC721("Olympus Agent", "OAGT") {
        treasury = _treasury;
    }

    function setVerifier(address _verifier) external {

        require(verifier == address(0), "Already set");
        verifier = _verifier;
    }

    function registerAgent(string calldata metadataURI)
        external
        payable
        nonReentrant
        returns (uint256 tokenId)
    {
        if (msg.value < MIN_STAKE) revert InsufficientStake();
        if (operatorToId[msg.sender] != 0) revert AlreadyRegistered();

        tokenId = ++_tokenIdCounter;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);

        operatorToId[msg.sender] = tokenId;
        AgentData storage agent = agentData[tokenId];
        agent.operator = msg.sender;
        agent.stake = msg.value;
        agent.reputationScore = INITIAL_REPUTATION;
        agent.active = true;

        emit AgentRegistered(tokenId, msg.sender, metadataURI);
    }

    function getAgentURI(uint256 tokenId) external view returns (string memory) {
        return tokenURI(tokenId);
    }

    function agentOf(address operator) external view returns (uint256 tokenId) {
        return operatorToId[operator];
    }

    function setCapabilities(uint256 agentId, bytes32[] calldata caps) external agentExists(agentId) {
        require(msg.sender == agentData[agentId].operator, "Not operator");
        agentData[agentId].capabilities = caps;
    }

    function hasCapability(uint256 agentId, bytes32 cap) external view returns (bool) {
        bytes32[] storage caps = agentData[agentId].capabilities;
        for (uint256 i = 0; i < caps.length; i++) {
            if (caps[i] == cap) return true;
        }
        return false;
    }

    function postFeedback(uint256 agentId, bool success, uint256 latencyMs, bytes calldata)
        external
        onlyVerifier
        agentExists(agentId)
    {
        AgentData storage agent = agentData[agentId];

        uint256 latencyPenalty = latencyMs > 10_000 ? 500 : (latencyMs * 500) / 10_000;
        uint256 outcomeScore = success ? (MAX_REPUTATION - latencyPenalty) : 0;
        agent.reputationScore = (agent.reputationScore * 90 + outcomeScore * 10) / 100;

        if (success) {
            agent.tasksCompleted++;

            agent.missCount = 0;
        } else {
            agent.tasksFailed++;
            _handleMiss(agentId, agent);
        }

        emit FeedbackPosted(agentId, success, agent.reputationScore);
    }

    function getFeedback(uint256 agentId)
        external
        view
        returns (uint256 score, uint256 totalInteractions)
    {
        AgentData storage agent = agentData[agentId];
        return (agent.reputationScore, agent.tasksCompleted + agent.tasksFailed);
    }

    function requestValidation(uint256 agentId, bytes32 taskId, bytes calldata proof)
        external
        returns (bytes32 requestId)
    {
        requestId = keccak256(abi.encodePacked(agentId, taskId, proof, block.timestamp));
        emit ValidationRequested(requestId, agentId, taskId);
    }

    function recordValidation(bytes32 requestId, bool valid, bytes calldata)
        external
        onlyVerifier
    {
        emit ValidationRecorded(requestId, valid);
    }

    function maxConcurrentClaims(uint256 agentId) external view returns (uint256) {
        return agentData[agentId].stake / STAKE_PER_CLAIM_SLOT;
    }

    function addStake(uint256 agentId) external payable agentExists(agentId) {
        require(msg.sender == agentData[agentId].operator, "Not operator");
        agentData[agentId].stake += msg.value;
    }

    function deregister(uint256 agentId) external nonReentrant agentExists(agentId) {
        AgentData storage agent = agentData[agentId];
        require(msg.sender == agent.operator, "Not operator");
        require(agent.active, "Already inactive");

        agent.active = false;
        uint256 refund = agent.stake;
        agent.stake = 0;

        (bool ok,) = agent.operator.call{value: refund}("");
        if (!ok) revert WithdrawFailed();
    }

    function _handleMiss(uint256, AgentData storage agent) internal {
        if (agent.missCount == 0 || block.timestamp > agent.firstMissAt + MISS_WINDOW) {

            agent.missCount = 1;
            agent.firstMissAt = block.timestamp;
        } else {
            agent.missCount++;
            if (agent.missCount == 2) {

                uint256 slash = (agent.stake * MISS_SLASH_BPS) / 10_000;
                agent.stake -= slash;
                (bool ok,) = treasury.call{value: slash}("");
                require(ok, "Slash transfer failed");
            } else if (agent.missCount >= 3) {

                agent.active = false;
                uint256 refund = agent.stake;
                agent.stake = 0;
                (bool ok,) = agent.operator.call{value: refund}("");
                require(ok, "Refund failed");
            }
        }
        agent.claimBondsForfeited++;
    }
}
