// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC8004Validation.sol";
import "./TaskRegistry.sol";
import "./AgentRegistry.sol";
import "./SomniaAgentsAdapter.sol";

/// @notice ERC-8004 Validation Registry hook.
/// Implements optimistic proof acceptance with a 1-hour dispute window.
/// Flow: submitProof → verifyAndSettle (records pending) → finalizeExecution (releases bounty)
///       OR → disputeExecution (within window, re-validates on-chain, slashes if invalid)
contract ExecutionVerifier is IERC8004Validation {
    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant DISPUTE_WINDOW = 1 hours;

    // ─── Types ───────────────────────────────────────────────────────────────

    struct PendingSettlement {
        bytes32 proofTxHash;
        address agent;
        uint256 submittedAt;
        uint256 latencyMs;
        bool    finalized;
        bool    disputed;
    }

    // ─── Storage ─────────────────────────────────────────────────────────────

    mapping(uint256 taskId => PendingSettlement) public pending;

    TaskRegistry          public immutable taskRegistry;
    AgentRegistry         public immutable agentRegistry;
    SomniaAgentsAdapter   public immutable somniaAdapter; // may be address(0) on local test

    // ─── Events ──────────────────────────────────────────────────────────────

    event ProofPending(uint256 indexed taskId, address indexed agent, bytes32 proofTxHash, uint256 disputeDeadline);
    event ExecutionFinalized(uint256 indexed taskId, address indexed agent);
    event DisputeRaised(uint256 indexed taskId, address indexed challenger);
    event DisputeResolved(uint256 indexed taskId, bool disputeSucceeded);

    // ─── Errors ──────────────────────────────────────────────────────────────

    error NotTaskRegistry();
    error NoPendingSettlement();
    error AlreadySettled();
    error DisputeWindowActive();
    error DisputeWindowExpired();
    error NotPoster();
    error TriggerConditionNotMet();

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _taskRegistry, address _agentRegistry, address _somniaAdapter) {
        taskRegistry  = TaskRegistry(_taskRegistry);
        agentRegistry = AgentRegistry(_agentRegistry);
        somniaAdapter = SomniaAgentsAdapter(_somniaAdapter);
    }

    // ─── IExecutionVerifier (called by TaskRegistry.submitProof) ─────────────

    /// @notice Records a pending settlement after validating the trigger condition on-chain.
    ///         Bounty stays locked in escrow until finalized or disputed.
    function verifyAndSettle(uint256 taskId, bytes32 proofTxHash, address agent) external {
        if (msg.sender != address(taskRegistry)) revert NotTaskRegistry();

        TaskRegistry.Task memory task = taskRegistry.getTask(taskId);

        // Re-evaluate trigger condition via Somnia Agents (skipped if no adapter or no condition)
        if (address(somniaAdapter) != address(0) && task.triggerCondition.length > 0) {
            bool triggered = somniaAdapter.evaluate(task.triggerCondition);
            if (!triggered) revert TriggerConditionNotMet();
        }

        uint256 latencyMs = (block.timestamp - task.claimedAt) * 1000;
        uint256 disputeDeadline = block.timestamp + DISPUTE_WINDOW;

        pending[taskId] = PendingSettlement({
            proofTxHash: proofTxHash,
            agent:       agent,
            submittedAt: block.timestamp,
            latencyMs:   latencyMs,
            finalized:   false,
            disputed:    false
        });

        bytes32 requestId = keccak256(abi.encodePacked(taskId, proofTxHash, agent));
        emit ValidationRequested(requestId, agentRegistry.agentOf(agent), bytes32(taskId));
        emit ProofPending(taskId, agent, proofTxHash, disputeDeadline);
    }

    // ─── Finalize (happy path, after dispute window) ──────────────────────────

    /// @notice Anyone can finalize a pending settlement once the dispute window has passed.
    function finalizeExecution(uint256 taskId) external {
        PendingSettlement storage ps = pending[taskId];
        if (ps.submittedAt == 0)              revert NoPendingSettlement();
        if (ps.finalized || ps.disputed)      revert AlreadySettled();
        if (block.timestamp < ps.submittedAt + DISPUTE_WINDOW) revert DisputeWindowActive();

        ps.finalized = true;

        taskRegistry.settleVerified(taskId, ps.proofTxHash, ps.agent, ps.latencyMs);

        bytes32 requestId = keccak256(abi.encodePacked(taskId, ps.proofTxHash, ps.agent));
        emit ValidationRecorded(requestId, true);
        emit ExecutionFinalized(taskId, ps.agent);
    }

    // ─── Dispute (within dispute window) ─────────────────────────────────────

    /// @notice Task poster can challenge the proof within DISPUTE_WINDOW.
    ///         Re-evaluates the trigger condition on-chain. If the condition is no longer
    ///         satisfied (or was never satisfied), the dispute succeeds: bounty is refunded
    ///         to the poster and the agent is penalized. If the condition still holds,
    ///         the dispute fails and the proof is confirmed valid.
    function disputeExecution(uint256 taskId) external {
        PendingSettlement storage ps = pending[taskId];
        if (ps.submittedAt == 0)          revert NoPendingSettlement();
        if (ps.finalized || ps.disputed)  revert AlreadySettled();
        if (block.timestamp >= ps.submittedAt + DISPUTE_WINDOW) revert DisputeWindowExpired();

        TaskRegistry.Task memory task = taskRegistry.getTask(taskId);
        if (msg.sender != task.poster) revert NotPoster();

        // Re-evaluate trigger at current block state
        bool proofValid = _revalidate(task.triggerCondition);

        ps.disputed = true;

        bytes32 requestId = keccak256(abi.encodePacked(taskId, ps.proofTxHash, ps.agent));

        if (!proofValid) {
            // Dispute succeeded: forfeit bond + refund bounty to poster, penalize agent
            taskRegistry.settleDisputed(taskId);
            emit ValidationRecorded(requestId, false);
            emit DisputeRaised(taskId, msg.sender);
            emit DisputeResolved(taskId, true);
        } else {
            // Dispute failed: proof was valid, finalize in agent's favour immediately
            taskRegistry.settleVerified(taskId, ps.proofTxHash, ps.agent, ps.latencyMs);
            emit ValidationRecorded(requestId, true);
            emit DisputeRaised(taskId, msg.sender);
            emit DisputeResolved(taskId, false);
        }
    }

    // ─── IERC8004Validation (pass-through stubs) ──────────────────────────────

    function requestValidation(uint256 agentId, bytes32 taskId, bytes calldata proof)
        external
        returns (bytes32 requestId)
    {
        requestId = keccak256(abi.encodePacked(agentId, taskId, proof, block.timestamp));
        emit ValidationRequested(requestId, agentId, taskId);
    }

    function recordValidation(bytes32 requestId, bool valid, bytes calldata) external {
        emit ValidationRecorded(requestId, valid);
    }

    // ─── Views ───────────────────────────────────────────────────────────────

    function isDisputable(uint256 taskId) external view returns (bool) {
        PendingSettlement storage ps = pending[taskId];
        return ps.submittedAt > 0
            && !ps.finalized
            && !ps.disputed
            && block.timestamp < ps.submittedAt + DISPUTE_WINDOW;
    }

    function isFinalizable(uint256 taskId) external view returns (bool) {
        PendingSettlement storage ps = pending[taskId];
        return ps.submittedAt > 0
            && !ps.finalized
            && !ps.disputed
            && block.timestamp >= ps.submittedAt + DISPUTE_WINDOW;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    // Reverts with OracleResultStale if cache is stale — poster must refresh oracle first.
    function _revalidate(bytes memory triggerCondition) internal view returns (bool) {
        if (address(somniaAdapter) == address(0) || triggerCondition.length == 0) {
            return true;
        }
        return somniaAdapter.evaluate(triggerCondition);
    }
}
