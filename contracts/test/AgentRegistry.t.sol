// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";
import "../src/interfaces/IERC8004Identity.sol";
import "../src/interfaces/IERC8004Reputation.sol";

contract AgentRegistryTest is Test {
    // Redeclare events for vm.expectEmit matching
    event AgentRegistered(uint256 indexed tokenId, address indexed operator, string metadataURI);
    event FeedbackPosted(uint256 indexed agentId, bool success, uint256 score);

    AgentRegistry registry;
    address treasury = makeAddr("treasury");
    address alice    = makeAddr("alice");
    address bob      = makeAddr("bob");
    address verifier = makeAddr("verifier");

    uint256 constant MIN_STAKE         = 0.01 ether;
    uint256 constant CLAIM_BOND        = 0.0001 ether;
    uint256 constant STAKE_PER_SLOT    = 0.005 ether;

    function setUp() public {
        registry = new AgentRegistry(treasury);
        registry.setVerifier(verifier);
        vm.deal(alice, 10 ether);
        vm.deal(bob,   10 ether);
    }

    // ─── Registration ────────────────────────────────────────────────────────

    function test_register_success() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        assertEq(tokenId, 1);
        assertEq(registry.ownerOf(tokenId), alice);
        assertEq(registry.agentOf(alice), tokenId);

        // auto-getter skips bytes32[] capabilities → 9 fields: operator,stake,rep,completed,failed,forfeited,missCount,firstMissAt,active
        (,uint256 stake, uint256 rep,,,,,, bool active) = registry.agentData(tokenId);
        assertEq(stake, MIN_STAKE);
        assertEq(rep, 500);
        assertTrue(active);
    }

    function test_register_emits_event() public {
        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(1, alice, "ipfs://alice");

        vm.prank(alice);
        registry.registerAgent{value: MIN_STAKE}("ipfs://alice");
    }

    function test_register_reverts_insufficient_stake() public {
        vm.prank(alice);
        vm.expectRevert(AgentRegistry.InsufficientStake.selector);
        registry.registerAgent{value: MIN_STAKE - 1}("ipfs://alice");
    }

    function test_register_reverts_duplicate() public {
        vm.startPrank(alice);
        registry.registerAgent{value: MIN_STAKE}("ipfs://alice");
        vm.expectRevert(AgentRegistry.AlreadyRegistered.selector);
        registry.registerAgent{value: MIN_STAKE}("ipfs://alice2");
        vm.stopPrank();
    }

    // ─── Capabilities ────────────────────────────────────────────────────────

    function test_set_and_query_capabilities() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        bytes32 SWAP = keccak256("SWAP");
        bytes32 TRANSFER = keccak256("TRANSFER");
        bytes32[] memory caps = new bytes32[](2);
        caps[0] = SWAP;
        caps[1] = TRANSFER;

        vm.prank(alice);
        registry.setCapabilities(id, caps);

        assertTrue(registry.hasCapability(id, SWAP));
        assertTrue(registry.hasCapability(id, TRANSFER));
        assertFalse(registry.hasCapability(id, keccak256("COMPOUND")));
    }

    function test_set_capabilities_reverts_non_operator() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        bytes32[] memory caps = new bytes32[](1);
        caps[0] = keccak256("SWAP");

        vm.prank(bob);
        vm.expectRevert("Not operator");
        registry.setCapabilities(id, caps);
    }

    // ─── maxConcurrentClaims ─────────────────────────────────────────────────

    function test_max_concurrent_claims_math() public {
        vm.prank(alice);
        // 0.01 ether stake / 0.005 per slot = 2 slots
        uint256 id = registry.registerAgent{value: 0.01 ether}("ipfs://alice");
        assertEq(registry.maxConcurrentClaims(id), 2);
    }

    function test_max_concurrent_claims_grows_with_stake() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: 0.05 ether}("ipfs://alice");
        assertEq(registry.maxConcurrentClaims(id), 10);
    }

    function testFuzz_max_concurrent_claims(uint256 extraStake) public {
        extraStake = bound(extraStake, 0, 5 ether);
        uint256 total = MIN_STAKE + extraStake;

        vm.deal(alice, total + 1 ether);
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: total}("ipfs://alice");

        assertEq(registry.maxConcurrentClaims(id), total / STAKE_PER_SLOT);
    }

    // ─── postFeedback / Reputation ───────────────────────────────────────────

    function test_feedback_success_increases_score_over_time() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        // 10 successful instant completions should drive score toward 1000
        vm.startPrank(verifier);
        for (uint256 i = 0; i < 10; i++) {
            registry.postFeedback(id, true, 0, "");
        }
        vm.stopPrank();

        (uint256 score,) = registry.getFeedback(id);
        assertGt(score, 500);
    }

    function test_feedback_failure_decreases_score() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.prank(verifier);
        registry.postFeedback(id, false, 0, "");

        (uint256 score,) = registry.getFeedback(id);
        assertLt(score, 500);
    }

    function test_feedback_reverts_non_verifier() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.prank(bob);
        vm.expectRevert(AgentRegistry.NotVerifier.selector);
        registry.postFeedback(id, true, 0, "");
    }

    function test_feedback_total_interactions_increments() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.startPrank(verifier);
        registry.postFeedback(id, true, 0, "");
        registry.postFeedback(id, false, 0, "");
        vm.stopPrank();

        (, uint256 total) = registry.getFeedback(id);
        assertEq(total, 2);
    }

    // ─── Miss streak / slash logic ────────────────────────────────────────────

    function test_second_miss_within_window_slashes_stake() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");
        uint256 stakeBefore = MIN_STAKE;

        vm.startPrank(verifier);
        registry.postFeedback(id, false, 0, ""); // miss 1 — no slash
        registry.postFeedback(id, false, 0, ""); // miss 2 — 10% slash
        vm.stopPrank();

        (,uint256 stakeAfter,,,,,,,) = registry.agentData(id);
        assertEq(stakeAfter, stakeBefore - (stakeBefore * 1000 / 10_000));
        assertGt(treasury.balance, 0);
    }

    function test_third_miss_auto_deregisters() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.startPrank(verifier);
        registry.postFeedback(id, false, 0, "");
        registry.postFeedback(id, false, 0, "");
        registry.postFeedback(id, false, 0, ""); // miss 3 — deregister
        vm.stopPrank();

        (,,,,,,,,bool active) = registry.agentData(id);
        assertFalse(active);
    }

    function test_miss_resets_after_window() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.prank(verifier);
        registry.postFeedback(id, false, 0, ""); // miss 1

        // Advance past 24h window
        vm.warp(block.timestamp + 25 hours);

        // Miss again — starts a fresh window, no slash
        uint256 balBefore = treasury.balance;
        vm.prank(verifier);
        registry.postFeedback(id, false, 0, "");
        assertEq(treasury.balance, balBefore); // no slash happened
    }

    function test_success_resets_miss_count() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.startPrank(verifier);
        registry.postFeedback(id, false, 0, ""); // miss 1
        registry.postFeedback(id, true,  0, ""); // success — resets streak
        registry.postFeedback(id, false, 0, ""); // miss 1 again — no slash
        vm.stopPrank();

        // Only 1 miss in current window — treasury still empty
        assertEq(treasury.balance, 0);
    }

    // ─── Stake management ────────────────────────────────────────────────────

    function test_add_stake() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.prank(alice);
        registry.addStake{value: 0.01 ether}(id);

        (,uint256 stake,,,,,,,) = registry.agentData(id);
        assertEq(stake, MIN_STAKE + 0.01 ether);
    }

    function test_deregister_refunds_stake() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");
        uint256 balBefore = alice.balance;

        vm.prank(alice);
        registry.deregister(id);

        assertEq(alice.balance, balBefore + MIN_STAKE);
        (,,,,,,,,bool active) = registry.agentData(id);
        assertFalse(active);
    }

    function test_deregister_reverts_non_operator() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.prank(bob);
        vm.expectRevert("Not operator");
        registry.deregister(id);
    }

    // ─── setVerifier ─────────────────────────────────────────────────────────

    function test_set_verifier_only_once() public {
        AgentRegistry fresh = new AgentRegistry(treasury);
        fresh.setVerifier(verifier);
        vm.expectRevert("Already set");
        fresh.setVerifier(bob);
    }
}
