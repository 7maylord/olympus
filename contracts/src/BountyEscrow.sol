// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Holds task bounties and claim bonds for the lifetime of each task.
/// Only the TaskRegistry (set once at deploy) can deposit, release, or forfeit funds.
contract BountyEscrow is ReentrancyGuard {
    // ─── Storage ─────────────────────────────────────────────────────────────

    struct EscrowEntry {
        uint256 bounty;     // poster's bounty
        uint256 claimBond;  // agent's claim bond (0 if unclaimed)
        address agent;      // zero if unclaimed
    }

    mapping(uint256 taskId => EscrowEntry) private _entries;

    address public taskRegistry;
    address public treasury;

    // ─── Events ──────────────────────────────────────────────────────────────

    event BountyDeposited(uint256 indexed taskId, uint256 amount);
    event ClaimBondDeposited(uint256 indexed taskId, address indexed agent, uint256 amount);
    event BountyReleased(uint256 indexed taskId, address indexed recipient, uint256 amount);
    event BountyRefunded(uint256 indexed taskId, address indexed poster, uint256 amount);
    event ClaimBondForfeited(uint256 indexed taskId, address indexed agent, uint256 amount);
    event ClaimBondReturned(uint256 indexed taskId, address indexed agent, uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────────────

    error NotTaskRegistry();
    error AlreadyDeposited();
    error NoBounty();
    error NoBond();
    error TransferFailed();

    // ─── Modifier ────────────────────────────────────────────────────────────

    modifier onlyTaskRegistry() {
        if (msg.sender != taskRegistry) revert NotTaskRegistry();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _treasury) {
        treasury = _treasury;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setTaskRegistry(address _taskRegistry) external {
        require(taskRegistry == address(0), "Already set");
        taskRegistry = _taskRegistry;
    }

    // ─── Deposit ─────────────────────────────────────────────────────────────

    /// Called by TaskRegistry when a task is posted. msg.value is the bounty.
    function depositBounty(uint256 taskId) external payable onlyTaskRegistry {
        if (_entries[taskId].bounty != 0) revert AlreadyDeposited();
        _entries[taskId].bounty = msg.value;
        emit BountyDeposited(taskId, msg.value);
    }

    /// Called by TaskRegistry when an agent claims. msg.value is the claim bond.
    function depositClaimBond(uint256 taskId, address agent) external payable onlyTaskRegistry {
        EscrowEntry storage e = _entries[taskId];
        if (e.bounty == 0) revert NoBounty();
        e.claimBond = msg.value;
        e.agent = agent;
        emit ClaimBondDeposited(taskId, agent, msg.value);
    }

    // ─── Settlement ──────────────────────────────────────────────────────────

    /// Happy path: execution verified. Releases bounty + returns claim bond to agent.
    function settleSuccess(uint256 taskId, address agent) external nonReentrant onlyTaskRegistry {
        EscrowEntry storage e = _entries[taskId];
        uint256 bounty = e.bounty;
        uint256 bond = e.claimBond;
        if (bounty == 0) revert NoBounty();

        e.bounty = 0;
        e.claimBond = 0;
        e.agent = address(0);

        // Return bond first (smaller, less likely to fail)
        if (bond > 0) {
            _transfer(agent, bond);
            emit ClaimBondReturned(taskId, agent, bond);
        }

        _transfer(agent, bounty);
        emit BountyReleased(taskId, agent, bounty);
    }

    /// Claim expired without execution: forfeit bond to treasury, release task back to Open.
    function forfeitBond(uint256 taskId) external nonReentrant onlyTaskRegistry {
        EscrowEntry storage e = _entries[taskId];
        uint256 bond = e.claimBond;
        address agent = e.agent;
        if (bond == 0) revert NoBond();

        e.claimBond = 0;
        e.agent = address(0);
        // bounty stays locked — task goes back to Open

        _transfer(treasury, bond);
        emit ClaimBondForfeited(taskId, agent, bond);
    }

    /// Task expired while Open (never claimed), or dispute resolved in poster's favor.
    function refundBounty(uint256 taskId, address poster) external nonReentrant onlyTaskRegistry {
        EscrowEntry storage e = _entries[taskId];
        uint256 bounty = e.bounty;
        if (bounty == 0) revert NoBounty();

        e.bounty = 0;
        e.claimBond = 0;
        e.agent = address(0);

        _transfer(poster, bounty);
        emit BountyRefunded(taskId, poster, bounty);
    }

    // ─── Views ───────────────────────────────────────────────────────────────

    function getEntry(uint256 taskId) external view returns (uint256 bounty, uint256 claimBond, address agent) {
        EscrowEntry storage e = _entries[taskId];
        return (e.bounty, e.claimBond, e.agent);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    function _transfer(address to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
