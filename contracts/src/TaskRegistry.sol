// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AgentRegistry.sol";
import "./BountyEscrow.sol";

interface ITaskSettlement {
    function settleVerified(uint256 taskId, bytes32 proofTxHash, address agent, uint256 latencyMs) external;
    function settleDisputed(uint256 taskId) external;
}

contract TaskRegistry is ReentrancyGuard, ITaskSettlement {

    uint256 public constant MIN_BOUNTY           = 0.001 ether;
    uint256 public constant LISTING_FEE          = 0.0001 ether;
    uint256 public constant CLAIM_BOND           = 0.0001 ether;
    uint256 public constant DEFAULT_CLAIM_WINDOW = 60;

    enum TaskStatus { Open, Claimed, Executed, Expired, Disputed }

    struct Task {
        address poster;
        bytes32 capabilityTag;
        bytes   triggerCondition;
        bytes   targetAction;
        uint256 bounty;
        uint256 expiry;
        uint256 minAgentReputation;
        TaskStatus status;
        address claimedBy;
        uint256 claimedAt;
        uint256 claimWindowSeconds;
    }

    mapping(uint256 => Task) private _tasks;
    mapping(uint256 agentId => uint256 count) public activeClaims;

    uint256 private _taskIdCounter;

    AgentRegistry public immutable agentRegistry;
    BountyEscrow  public immutable bountyEscrow;
    address       public executionVerifier;
    address       public immutable treasury;

    event TaskPosted(uint256 indexed taskId, bytes32 indexed capabilityTag, uint256 bounty, uint256 expiry);
    event TaskClaimed(uint256 indexed taskId, address indexed agent, uint256 claimBond);
    event TaskExecuted(uint256 indexed taskId, address indexed agent, bytes32 proofHash, uint256 latencyMs);
    event TaskExpired(uint256 indexed taskId, bool bondForfeited);
    event TaskDisputed(uint256 indexed taskId, address indexed challenger);

    error TaskNotFound();
    error TaskNotOpen();
    error TaskNotClaimed();
    error TaskAlreadyExpired();
    error WrongClaimBond();
    error AgentNotRegistered();
    error InsufficientReputation();
    error ClaimLimitReached();
    error NotClaimer();
    error ClaimWindowExpired();
    error InsufficientValue();
    error InvalidExpiry();
    error NotExecutionVerifier();
    error CannotExpire();
    error ClaimWindowActive();

    modifier onlyExecutionVerifier() {
        if (msg.sender != executionVerifier) revert NotExecutionVerifier();
        _;
    }

    constructor(address _agentRegistry, address _bountyEscrow, address _treasury) {
        agentRegistry = AgentRegistry(_agentRegistry);
        bountyEscrow  = BountyEscrow(_bountyEscrow);
        treasury      = _treasury;
    }

    function setExecutionVerifier(address _verifier) external {
        require(executionVerifier == address(0), "Already set");
        executionVerifier = _verifier;
    }

    function postTask(
        bytes32 capabilityTag,
        bytes calldata triggerCondition,
        bytes calldata targetAction,
        uint256 minAgentReputation,
        uint256 expiry,
        uint256 claimWindowSeconds
    ) external payable nonReentrant returns (uint256 taskId) {
        if (msg.value < MIN_BOUNTY + LISTING_FEE) revert InsufficientValue();
        if (expiry <= block.timestamp) revert InvalidExpiry();

        uint256 bounty = msg.value - LISTING_FEE;
        taskId = ++_taskIdCounter;
        uint256 window = claimWindowSeconds == 0 ? DEFAULT_CLAIM_WINDOW : claimWindowSeconds;

        _tasks[taskId] = Task({
            poster:             msg.sender,
            capabilityTag:      capabilityTag,
            triggerCondition:   triggerCondition,
            targetAction:       targetAction,
            bounty:             bounty,
            expiry:             expiry,
            minAgentReputation: minAgentReputation,
            status:             TaskStatus.Open,
            claimedBy:          address(0),
            claimedAt:          0,
            claimWindowSeconds: window
        });

        (bool ok,) = treasury.call{value: LISTING_FEE}("");
        require(ok, "Fee transfer failed");
        bountyEscrow.depositBounty{value: bounty}(taskId);

        emit TaskPosted(taskId, capabilityTag, bounty, expiry);
    }

    function claimTask(uint256 taskId) external payable nonReentrant {
        Task storage task = _tasks[taskId];
        if (task.poster == address(0))           revert TaskNotFound();
        if (task.status != TaskStatus.Open)      revert TaskNotOpen();
        if (block.timestamp >= task.expiry)      revert TaskAlreadyExpired();
        if (msg.value != CLAIM_BOND)             revert WrongClaimBond();

        uint256 agentId = agentRegistry.agentOf(msg.sender);
        if (agentId == 0) revert AgentNotRegistered();

        (uint256 rep,) = agentRegistry.getFeedback(agentId);
        if (rep < task.minAgentReputation) revert InsufficientReputation();

        if (activeClaims[agentId] >= agentRegistry.maxConcurrentClaims(agentId)) {
            revert ClaimLimitReached();
        }

        task.status    = TaskStatus.Claimed;
        task.claimedBy = msg.sender;
        task.claimedAt = block.timestamp;
        activeClaims[agentId]++;

        bountyEscrow.depositClaimBond{value: msg.value}(taskId, msg.sender);

        emit TaskClaimed(taskId, msg.sender, msg.value);
    }

    function submitProof(uint256 taskId, bytes32 proofTxHash) external nonReentrant {
        Task storage task = _tasks[taskId];
        if (task.status != TaskStatus.Claimed)                              revert TaskNotClaimed();
        if (task.claimedBy != msg.sender)                                   revert NotClaimer();
        if (block.timestamp > task.claimedAt + task.claimWindowSeconds)     revert ClaimWindowExpired();

        if (executionVerifier != address(0)) {

            IExecutionVerifier(executionVerifier).verifyAndSettle(taskId, proofTxHash, msg.sender);
        } else {

            uint256 latencyMs = (block.timestamp - task.claimedAt) * 1000;
            _settleSuccess(taskId, proofTxHash, msg.sender, latencyMs);
        }
    }

    function settleVerified(uint256 taskId, bytes32 proofTxHash, address agent, uint256 latencyMs)
        external
        nonReentrant
        onlyExecutionVerifier
    {
        _settleSuccess(taskId, proofTxHash, agent, latencyMs);
    }

    function settleDisputed(uint256 taskId) external nonReentrant onlyExecutionVerifier {
        Task storage task = _tasks[taskId];
        task.status = TaskStatus.Disputed;

        uint256 agentId = agentRegistry.agentOf(task.claimedBy);
        activeClaims[agentId]--;

        bountyEscrow.forfeitBond(taskId);
        bountyEscrow.refundBounty(taskId, task.poster);
        agentRegistry.postFeedback(agentId, false, 0, "");

        emit TaskDisputed(taskId, task.poster);
    }

    function expireTask(uint256 taskId) external nonReentrant {
        Task storage task = _tasks[taskId];
        if (task.poster == address(0)) revert TaskNotFound();

        if (task.status == TaskStatus.Claimed) {

            if (block.timestamp <= task.claimedAt + task.claimWindowSeconds) revert ClaimWindowActive();

            uint256 agentId = agentRegistry.agentOf(task.claimedBy);
            activeClaims[agentId]--;
            agentRegistry.postFeedback(agentId, false, 0, "");

            task.status    = TaskStatus.Open;
            task.claimedBy = address(0);
            task.claimedAt = 0;

            bountyEscrow.forfeitBond(taskId);
            emit TaskExpired(taskId, true);

        } else if (task.status == TaskStatus.Open) {
            if (block.timestamp <= task.expiry) revert CannotExpire();

            task.status = TaskStatus.Expired;
            bountyEscrow.refundBounty(taskId, task.poster);
            emit TaskExpired(taskId, false);

        } else {
            revert CannotExpire();
        }
    }

    function getTask(uint256 taskId) external view returns (Task memory) {
        if (_tasks[taskId].poster == address(0)) revert TaskNotFound();
        return _tasks[taskId];
    }

    function taskCount() external view returns (uint256) {
        return _taskIdCounter;
    }

    function _settleSuccess(uint256 taskId, bytes32 proofTxHash, address agent, uint256 latencyMs) internal {
        Task storage task = _tasks[taskId];
        task.status = TaskStatus.Executed;

        uint256 agentId = agentRegistry.agentOf(agent);
        activeClaims[agentId]--;

        bountyEscrow.settleSuccess(taskId, agent);
        agentRegistry.postFeedback(agentId, true, latencyMs, "");

        emit TaskExecuted(taskId, agent, proofTxHash, latencyMs);
    }
}

interface IExecutionVerifier {
    function verifyAndSettle(uint256 taskId, bytes32 proofTxHash, address agent) external;
}
