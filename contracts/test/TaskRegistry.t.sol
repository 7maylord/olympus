// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TaskRegistry.sol";
import "../src/AgentRegistry.sol";
import "../src/BountyEscrow.sol";

contract TaskRegistryTest is Test {
    TaskRegistry registry;
    AgentRegistry agentRegistry;
    BountyEscrow  escrow;

    address treasury = makeAddr("treasury");
    address poster   = makeAddr("poster");
    address alice    = makeAddr("alice");   // agent operator
    address bob      = makeAddr("bob");     // second agent operator

    uint256 constant MIN_STAKE   = 0.01 ether;
    uint256 constant CLAIM_BOND  = 0.0001 ether;
    uint256 constant MIN_BOUNTY  = 0.001 ether;
    uint256 constant LISTING_FEE = 0.0001 ether;
    uint256 constant TOTAL_VALUE = MIN_BOUNTY + LISTING_FEE;

    bytes32 constant SWAP_TAG = keccak256("SWAP");

    // Redeclare events for vm.expectEmit
    event TaskPosted(uint256 indexed taskId, bytes32 indexed capabilityTag, uint256 bounty, uint256 expiry);
    event TaskClaimed(uint256 indexed taskId, address indexed agent, uint256 claimBond);
    event TaskExecuted(uint256 indexed taskId, address indexed agent, bytes32 proofHash, uint256 latencyMs);
    event TaskExpired(uint256 indexed taskId, bool bondForfeited);

    function setUp() public {
        agentRegistry = new AgentRegistry(treasury);
        escrow        = new BountyEscrow(treasury);
        registry      = new TaskRegistry(address(agentRegistry), address(escrow), treasury);

        // Wire contracts together
        agentRegistry.setVerifier(address(registry));
        escrow.setTaskRegistry(address(registry));

        vm.deal(poster, 100 ether);
        vm.deal(alice,  10 ether);
        vm.deal(bob,    10 ether);

        // Register alice as an agent
        vm.prank(alice);
        agentRegistry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        // Register bob as an agent
        vm.prank(bob);
        agentRegistry.registerAgent{value: MIN_STAKE}("ipfs://bob");
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _postTask() internal returns (uint256 taskId) {
        vm.prank(poster);
        taskId = registry.postTask{value: TOTAL_VALUE}(
            SWAP_TAG,
            abi.encode("trigger"),
            abi.encode("action"),
            0,                             // no rep requirement
            block.timestamp + 1 days,
            60
        );
    }

    function _postAndClaim() internal returns (uint256 taskId) {
        taskId = _postTask();
        vm.prank(alice);
        registry.claimTask{value: CLAIM_BOND}(taskId);
    }

    // ─── postTask ────────────────────────────────────────────────────────────

    function test_post_task_stores_fields() public {
        uint256 expiry = block.timestamp + 1 days;
        vm.prank(poster);
        uint256 taskId = registry.postTask{value: TOTAL_VALUE}(
            SWAP_TAG, abi.encode("t"), abi.encode("a"), 100, expiry, 60
        );

        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(t.poster,             poster);
        assertEq(t.capabilityTag,      SWAP_TAG);
        assertEq(t.bounty,             MIN_BOUNTY);
        assertEq(t.expiry,             expiry);
        assertEq(t.minAgentReputation, 100);
        assertEq(t.claimWindowSeconds, 60);
        assertEq(uint8(t.status),      uint8(TaskRegistry.TaskStatus.Open));
    }

    function test_post_task_escrows_bounty() public {
        _postTask();
        (uint256 bounty,,) = escrow.getEntry(1);
        assertEq(bounty, MIN_BOUNTY);
    }

    function test_post_task_sends_listing_fee() public {
        uint256 before = treasury.balance;
        _postTask();
        assertEq(treasury.balance, before + LISTING_FEE);
    }

    function test_post_task_emits_event() public {
        uint256 expiry = block.timestamp + 1 days;
        vm.expectEmit(true, true, false, true);
        emit TaskPosted(1, SWAP_TAG, MIN_BOUNTY, expiry);

        vm.prank(poster);
        registry.postTask{value: TOTAL_VALUE}(SWAP_TAG, "", "", 0, expiry, 60);
    }

    function test_post_task_reverts_insufficient_value() public {
        vm.prank(poster);
        vm.expectRevert(TaskRegistry.InsufficientValue.selector);
        registry.postTask{value: TOTAL_VALUE - 1}(SWAP_TAG, "", "", 0, block.timestamp + 1 days, 60);
    }

    function test_post_task_reverts_past_expiry() public {
        vm.prank(poster);
        vm.expectRevert(TaskRegistry.InvalidExpiry.selector);
        registry.postTask{value: TOTAL_VALUE}(SWAP_TAG, "", "", 0, block.timestamp, 60);
    }

    function test_post_task_increments_counter() public {
        _postTask();
        _postTask();
        assertEq(registry.taskCount(), 2);
    }

    function test_post_task_default_claim_window() public {
        vm.prank(poster);
        uint256 taskId = registry.postTask{value: TOTAL_VALUE}(SWAP_TAG, "", "", 0, block.timestamp + 1 days, 0);
        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(t.claimWindowSeconds, 60); // DEFAULT_CLAIM_WINDOW
    }

    // ─── claimTask ───────────────────────────────────────────────────────────

    function test_claim_task_success() public {
        uint256 taskId = _postTask();

        vm.prank(alice);
        registry.claimTask{value: CLAIM_BOND}(taskId);

        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(uint8(t.status),    uint8(TaskRegistry.TaskStatus.Claimed));
        assertEq(t.claimedBy,        alice);
        assertEq(t.claimedAt,        block.timestamp);
    }

    function test_claim_task_deposits_bond_to_escrow() public {
        uint256 taskId = _postAndClaim();
        (, uint256 bond, address storedAgent) = escrow.getEntry(taskId);
        assertEq(bond, CLAIM_BOND);
        assertEq(storedAgent, alice);
    }

    function test_claim_task_emits_event() public {
        uint256 taskId = _postTask();

        vm.expectEmit(true, true, false, true);
        emit TaskClaimed(taskId, alice, CLAIM_BOND);

        vm.prank(alice);
        registry.claimTask{value: CLAIM_BOND}(taskId);
    }

    function test_claim_task_increments_active_claims() public {
        uint256 taskId = _postTask();
        uint256 agentId = agentRegistry.agentOf(alice);

        vm.prank(alice);
        registry.claimTask{value: CLAIM_BOND}(taskId);

        assertEq(registry.activeClaims(agentId), 1);
    }

    function test_claim_task_reverts_wrong_bond() public {
        uint256 taskId = _postTask();
        vm.prank(alice);
        vm.expectRevert(TaskRegistry.WrongClaimBond.selector);
        registry.claimTask{value: CLAIM_BOND - 1}(taskId);
    }

    function test_claim_task_reverts_not_open() public {
        uint256 taskId = _postAndClaim();
        vm.prank(bob);
        vm.expectRevert(TaskRegistry.TaskNotOpen.selector);
        registry.claimTask{value: CLAIM_BOND}(taskId);
    }

    function test_claim_task_reverts_expired() public {
        uint256 taskId = _postTask();
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        vm.expectRevert(TaskRegistry.TaskAlreadyExpired.selector);
        registry.claimTask{value: CLAIM_BOND}(taskId);
    }

    function test_claim_task_reverts_not_registered() public {
        uint256 taskId = _postTask();
        address rando = makeAddr("rando");
        vm.deal(rando, 1 ether);

        vm.prank(rando);
        vm.expectRevert(TaskRegistry.AgentNotRegistered.selector);
        registry.claimTask{value: CLAIM_BOND}(taskId);
    }

    function test_claim_task_reverts_insufficient_reputation() public {
        uint256 taskId;
        vm.prank(poster);
        taskId = registry.postTask{value: TOTAL_VALUE}(
            SWAP_TAG, "", "", 900, block.timestamp + 1 days, 60
        );

        vm.prank(alice);
        vm.expectRevert(TaskRegistry.InsufficientReputation.selector);
        registry.claimTask{value: CLAIM_BOND}(taskId);
    }

    function test_claim_task_reverts_concurrent_limit() public {
        // Alice has 0.01 ether stake → 2 claim slots
        // Post 3 tasks and claim 2 with alice
        uint256 t1 = _postTask();
        uint256 t2 = _postTask();
        uint256 t3 = _postTask();

        vm.startPrank(alice);
        registry.claimTask{value: CLAIM_BOND}(t1);
        registry.claimTask{value: CLAIM_BOND}(t2);

        vm.expectRevert(TaskRegistry.ClaimLimitReached.selector);
        registry.claimTask{value: CLAIM_BOND}(t3);
        vm.stopPrank();
    }

    // ─── submitProof (optimistic — no verifier wired) ─────────────────────────

    function test_submit_proof_settles_task() public {
        uint256 taskId  = _postAndClaim();
        uint256 agentId = agentRegistry.agentOf(alice);
        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        registry.submitProof(taskId, bytes32("proofhash"));

        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
        // Alice should receive bounty + claim bond back
        assertGt(alice.balance, aliceBefore);
        // Active claims decremented
        assertEq(registry.activeClaims(agentId), 0);
    }

    function test_submit_proof_updates_reputation() public {
        uint256 taskId  = _postAndClaim();
        uint256 agentId = agentRegistry.agentOf(alice);
        (uint256 repBefore,) = agentRegistry.getFeedback(agentId);

        vm.prank(alice);
        registry.submitProof(taskId, bytes32("proofhash"));

        (uint256 repAfter,) = agentRegistry.getFeedback(agentId);
        // Successful fast execution should increase or hold score
        assertGe(repAfter, repBefore);
    }

    function test_submit_proof_emits_event() public {
        uint256 taskId = _postAndClaim();

        vm.expectEmit(true, true, false, false); // ignore latencyMs (time-dependent)
        emit TaskExecuted(taskId, alice, bytes32("proofhash"), 0);

        vm.prank(alice);
        registry.submitProof(taskId, bytes32("proofhash"));
    }

    function test_submit_proof_reverts_not_claimer() public {
        uint256 taskId = _postAndClaim();
        vm.prank(bob);
        vm.expectRevert(TaskRegistry.NotClaimer.selector);
        registry.submitProof(taskId, bytes32("hash"));
    }

    function test_submit_proof_reverts_not_claimed() public {
        uint256 taskId = _postTask();
        vm.prank(alice);
        vm.expectRevert(TaskRegistry.TaskNotClaimed.selector);
        registry.submitProof(taskId, bytes32("hash"));
    }

    function test_submit_proof_reverts_window_expired() public {
        uint256 taskId = _postAndClaim();
        vm.warp(block.timestamp + 61); // past 60s window

        vm.prank(alice);
        vm.expectRevert(TaskRegistry.ClaimWindowExpired.selector);
        registry.submitProof(taskId, bytes32("hash"));
    }

    // ─── expireTask ───────────────────────────────────────────────────────────

    function test_expire_claimed_task_forfeits_bond() public {
        uint256 taskId  = _postAndClaim();
        uint256 agentId = agentRegistry.agentOf(alice);
        vm.warp(block.timestamp + 61); // past claim window

        uint256 treasuryBefore = treasury.balance;

        vm.prank(makeAddr("anyone"));
        registry.expireTask(taskId);

        // Bond forfeited to treasury
        assertEq(treasury.balance, treasuryBefore + CLAIM_BOND);
        // Task reset to Open
        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Open));
        assertEq(t.claimedBy, address(0));
        // Active claims decremented
        assertEq(registry.activeClaims(agentId), 0);
    }

    function test_expire_claimed_task_emits_event() public {
        uint256 taskId = _postAndClaim();
        vm.warp(block.timestamp + 61);

        vm.expectEmit(true, false, false, true);
        emit TaskExpired(taskId, true);

        registry.expireTask(taskId);
    }

    function test_expire_claimed_task_reverts_window_active() public {
        uint256 taskId = _postAndClaim();
        vm.expectRevert(TaskRegistry.ClaimWindowActive.selector);
        registry.expireTask(taskId);
    }

    function test_expire_open_task_refunds_poster() public {
        uint256 taskId = _postTask();
        uint256 posterBefore = poster.balance;

        vm.warp(block.timestamp + 2 days);
        registry.expireTask(taskId);

        assertEq(poster.balance, posterBefore + MIN_BOUNTY);
        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Expired));
    }

    function test_expire_open_task_reverts_before_expiry() public {
        uint256 taskId = _postTask();
        vm.expectRevert(TaskRegistry.CannotExpire.selector);
        registry.expireTask(taskId);
    }

    function test_expire_executed_task_reverts() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        registry.submitProof(taskId, bytes32("hash"));

        vm.expectRevert(TaskRegistry.CannotExpire.selector);
        registry.expireTask(taskId);
    }

    // ─── Full lifecycle ───────────────────────────────────────────────────────

    function test_full_lifecycle_post_claim_execute() public {
        uint256 taskId  = _postTask();
        uint256 agentId = agentRegistry.agentOf(alice);

        // Claim
        vm.prank(alice);
        registry.claimTask{value: CLAIM_BOND}(taskId);
        assertEq(registry.activeClaims(agentId), 1);

        // Execute
        vm.prank(alice);
        registry.submitProof(taskId, bytes32("txhash"));

        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
        assertEq(registry.activeClaims(agentId), 0);
        (uint256 score, uint256 total) = agentRegistry.getFeedback(agentId);
        assertEq(total, 1);
        assertGt(score, 0);
    }

    function test_full_lifecycle_claim_expire_reclaim() public {
        uint256 taskId = _postTask();

        // Alice claims but her window expires
        vm.prank(alice);
        registry.claimTask{value: CLAIM_BOND}(taskId);

        vm.warp(block.timestamp + 61);
        registry.expireTask(taskId); // task back to Open, alice's bond forfeited

        // Bob now claims the same task
        vm.prank(bob);
        registry.claimTask{value: CLAIM_BOND}(taskId);

        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(t.claimedBy, bob);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Claimed));
    }

    // ─── Claim race ───────────────────────────────────────────────────────────

    function test_only_one_agent_wins_claim_race() public {
        uint256 taskId = _postTask();

        // Alice wins the race
        vm.prank(alice);
        registry.claimTask{value: CLAIM_BOND}(taskId);

        // Bob tries second — task is no longer Open
        vm.prank(bob);
        vm.expectRevert(TaskRegistry.TaskNotOpen.selector);
        registry.claimTask{value: CLAIM_BOND}(taskId);
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_post_task_bounty_accounting(uint256 extra) public {
        extra = bound(extra, 0, 99 ether);
        uint256 value = TOTAL_VALUE + extra;
        vm.deal(poster, value + 1 ether);

        vm.prank(poster);
        uint256 taskId = registry.postTask{value: value}(SWAP_TAG, "", "", 0, block.timestamp + 1 days, 0);

        TaskRegistry.Task memory t = registry.getTask(taskId);
        assertEq(t.bounty, value - LISTING_FEE);

        (uint256 escrowed,,) = escrow.getEntry(taskId);
        assertEq(escrowed, value - LISTING_FEE);
    }
}
