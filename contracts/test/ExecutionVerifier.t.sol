// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ExecutionVerifier.sol";
import "../src/TaskRegistry.sol";
import "../src/AgentRegistry.sol";
import "../src/BountyEscrow.sol";
import "../src/SomniaAgentsAdapter.sol";

/// @dev Minimal mock for ISomniaAgents — calls onAgentResponse synchronously within createTask.
///      Returns price 1_000e18 (< 2_000e18 threshold → triggered) or 3_000e18 (not triggered).
contract MockSomniaAgents {
    bool public response;
    SomniaAgentsAdapter public adapter;
    uint256 public nextId;

    function setResponse(bool val) external { response = val; }
    function setAdapter(address a)  external { adapter = SomniaAgentsAdapter(a); }

    function createTask(uint256, bytes calldata taskData) external payable returns (uint256 id) {
        id = ++nextId;
        bytes memory result = abi.encode(response ? uint256(1_000e18) : uint256(3_000e18));
        adapter.onAgentResponse(id, taskData, result);
    }
}

contract ExecutionVerifierTest is Test {
    AgentRegistry       agentReg;
    BountyEscrow        escrow;
    TaskRegistry        taskReg;
    SomniaAgentsAdapter adapter;
    ExecutionVerifier   verifier;
    MockSomniaAgents    mockSomnia;

    address treasury = makeAddr("treasury");
    address poster   = makeAddr("poster");
    address alice    = makeAddr("alice");

    uint256 constant MIN_STAKE   = 0.01 ether;
    uint256 constant CLAIM_BOND  = 0.0001 ether;
    uint256 constant MIN_BOUNTY  = 0.001 ether;
    uint256 constant LISTING_FEE = 0.0001 ether;
    uint256 constant TOTAL_VALUE = MIN_BOUNTY + LISTING_FEE;

    bytes32 constant PROOF_HASH = bytes32("txhash");
    bytes32 constant SWAP_TAG   = keccak256("SWAP");

    // Redeclare events
    event ProofPending(uint256 indexed taskId, address indexed agent, bytes32 proofTxHash, uint256 disputeDeadline);
    event ExecutionFinalized(uint256 indexed taskId, address indexed agent);
    event DisputeRaised(uint256 indexed taskId, address indexed challenger);
    event DisputeResolved(uint256 indexed taskId, bool disputeSucceeded);

    function setUp() public {
        mockSomnia = new MockSomniaAgents();

        agentReg  = new AgentRegistry(treasury);
        escrow    = new BountyEscrow(treasury);

        // Deploy adapter pointing to mock Somnia
        adapter   = new SomniaAgentsAdapter(address(mockSomnia), "https://api.price-feed.xyz/v1/");

        // Deploy TaskRegistry (no verifier yet)
        taskReg   = new TaskRegistry(address(agentReg), address(escrow), treasury);

        // Deploy ExecutionVerifier
        verifier  = new ExecutionVerifier(address(taskReg), address(agentReg), address(adapter));

        // Wire everything up
        agentReg.setVerifier(address(taskReg));
        escrow.setTaskRegistry(address(taskReg));
        taskReg.setExecutionVerifier(address(verifier));
        mockSomnia.setAdapter(address(adapter));

        vm.deal(poster, 100 ether);
        vm.deal(alice,  10 ether);

        vm.prank(alice);
        agentReg.registerAgent{value: MIN_STAKE}("ipfs://alice");
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// Post a task with no trigger condition (no Somnia call needed)
    function _postAndClaim() internal returns (uint256 taskId) {
        vm.prank(poster);
        taskId = taskReg.postTask{value: TOTAL_VALUE}(
            SWAP_TAG, "", "", 0, block.timestamp + 1 days, 60
        );
        vm.prank(alice);
        taskReg.claimTask{value: CLAIM_BOND}(taskId);
    }

    /// Post a task with a price-below trigger condition
    function _postAndClaimWithTrigger(bytes memory trigger) internal returns (uint256 taskId) {
        vm.prank(poster);
        taskId = taskReg.postTask{value: TOTAL_VALUE}(
            SWAP_TAG, trigger, "", 0, block.timestamp + 1 days, 60
        );
        vm.prank(alice);
        taskReg.claimTask{value: CLAIM_BOND}(taskId);
    }

    function _priceTrigger(bool triggerBelow) internal view returns (bytes memory) {
        return adapter.encodePriceTrigger(address(1), 2_000e18, triggerBelow);
    }

    /// Prime the oracle cache so evaluate() doesn't revert with OracleResultStale.
    /// Call this (with mockSomnia.setResponse already set) before any submitProof or disputeExecution
    /// that involves a trigger condition.
    function _primeOracle(bool triggerBelow) internal {
        adapter.requestOracleUpdate(_priceTrigger(triggerBelow));
    }

    // ─── verifyAndSettle ─────────────────────────────────────────────────────

    function test_verify_records_pending_settlement() public {
        uint256 taskId = _postAndClaim();

        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH); // routes to verifyAndSettle

        (bytes32 hash, address agent, uint256 submittedAt,,bool fin, bool disp) = verifier.pending(taskId);
        assertEq(hash,        PROOF_HASH);
        assertEq(agent,       alice);
        assertGt(submittedAt, 0);
        assertFalse(fin);
        assertFalse(disp);
    }

    function test_verify_emits_proof_pending() public {
        uint256 taskId = _postAndClaim();
        uint256 deadline = block.timestamp + verifier.DISPUTE_WINDOW();

        vm.expectEmit(true, true, false, true);
        emit ProofPending(taskId, alice, PROOF_HASH, deadline);

        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);
    }

    function test_verify_reverts_non_task_registry() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        vm.expectRevert(ExecutionVerifier.NotTaskRegistry.selector);
        verifier.verifyAndSettle(taskId, PROOF_HASH, alice);
    }

    function test_verify_with_trigger_condition_passes_when_met() public {
        mockSomnia.setResponse(true); // price = 1_000e18 < 2_000e18 → triggered
        uint256 taskId = _postAndClaimWithTrigger(_priceTrigger(true));
        _primeOracle(true);

        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH); // should not revert

        (, address agent,,,, ) = verifier.pending(taskId);
        assertEq(agent, alice);
    }

    function test_verify_reverts_when_trigger_not_met() public {
        mockSomnia.setResponse(false); // price = 3_000e18 > 2_000e18 → NOT triggered (below)
        uint256 taskId = _postAndClaimWithTrigger(_priceTrigger(true));
        _primeOracle(true); // primes cache with not-triggered result

        vm.prank(alice);
        vm.expectRevert(ExecutionVerifier.TriggerConditionNotMet.selector);
        taskReg.submitProof(taskId, PROOF_HASH);
    }

    // ─── finalizeExecution ────────────────────────────────────────────────────

    function test_finalize_after_window_pays_agent() public {
        uint256 taskId     = _postAndClaim();
        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);
        verifier.finalizeExecution(taskId);

        assertGt(alice.balance, aliceBefore);

        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
    }

    function test_finalize_anyone_can_call() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        verifier.finalizeExecution(taskId); // should not revert
    }

    function test_finalize_emits_event() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);

        vm.expectEmit(true, true, false, false);
        emit ExecutionFinalized(taskId, alice);
        verifier.finalizeExecution(taskId);
    }

    function test_finalize_marks_finalized_flag() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);
        verifier.finalizeExecution(taskId);

        (,,,, bool fin,) = verifier.pending(taskId);
        assertTrue(fin);
    }

    function test_finalize_reverts_during_dispute_window() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.expectRevert(ExecutionVerifier.DisputeWindowActive.selector);
        verifier.finalizeExecution(taskId);
    }

    function test_finalize_reverts_no_pending() public {
        vm.expectRevert(ExecutionVerifier.NoPendingSettlement.selector);
        verifier.finalizeExecution(99);
    }

    function test_finalize_reverts_double_finalize() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);
        verifier.finalizeExecution(taskId);

        vm.expectRevert(ExecutionVerifier.AlreadySettled.selector);
        verifier.finalizeExecution(taskId);
    }

    // ─── disputeExecution ─────────────────────────────────────────────────────

    function test_dispute_success_refunds_poster() public {
        mockSomnia.setResponse(true);
        uint256 taskId = _postAndClaimWithTrigger(_priceTrigger(true));
        _primeOracle(true); // cache: triggered
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        // Price recovered — update cache to not-triggered before disputing
        mockSomnia.setResponse(false);
        _primeOracle(true);
        uint256 posterBefore = poster.balance;

        vm.prank(poster);
        verifier.disputeExecution(taskId);

        assertGt(poster.balance, posterBefore); // bounty refunded
        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Disputed));
    }

    function test_dispute_success_forfeits_bond_to_treasury() public {
        mockSomnia.setResponse(true);
        uint256 taskId = _postAndClaimWithTrigger(_priceTrigger(true));
        _primeOracle(true);
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        mockSomnia.setResponse(false);
        _primeOracle(true);
        uint256 treasuryBefore = treasury.balance;

        vm.prank(poster);
        verifier.disputeExecution(taskId);

        assertEq(treasury.balance, treasuryBefore + CLAIM_BOND);
    }

    function test_dispute_success_emits_events() public {
        mockSomnia.setResponse(true);
        uint256 taskId = _postAndClaimWithTrigger(_priceTrigger(true));
        _primeOracle(true);
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        mockSomnia.setResponse(false);
        _primeOracle(true);

        vm.expectEmit(true, true, false, false);
        emit DisputeRaised(taskId, poster);
        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(taskId, true);

        vm.prank(poster);
        verifier.disputeExecution(taskId);
    }

    function test_dispute_fail_finalises_for_agent() public {
        // Trigger still met → dispute fails → agent gets paid immediately
        mockSomnia.setResponse(true);
        uint256 taskId  = _postAndClaimWithTrigger(_priceTrigger(true));
        _primeOracle(true);
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.prank(poster);
        verifier.disputeExecution(taskId); // trigger still met → dispute fails

        assertGt(alice.balance, aliceBefore);
        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
    }

    function test_dispute_fail_emits_resolved_false() public {
        mockSomnia.setResponse(true);
        uint256 taskId = _postAndClaimWithTrigger(_priceTrigger(true));
        _primeOracle(true);
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(taskId, false);

        vm.prank(poster);
        verifier.disputeExecution(taskId);
    }

    function test_dispute_reverts_after_window() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);

        vm.prank(poster);
        vm.expectRevert(ExecutionVerifier.DisputeWindowExpired.selector);
        verifier.disputeExecution(taskId);
    }

    function test_dispute_reverts_non_poster() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert(ExecutionVerifier.NotPoster.selector);
        verifier.disputeExecution(taskId);
    }

    function test_dispute_reverts_no_pending() public {
        vm.prank(poster);
        vm.expectRevert(ExecutionVerifier.NoPendingSettlement.selector);
        verifier.disputeExecution(99);
    }

    function test_dispute_reverts_already_finalized() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);
        verifier.finalizeExecution(taskId);

        vm.prank(poster);
        vm.expectRevert(ExecutionVerifier.AlreadySettled.selector);
        verifier.disputeExecution(taskId);
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    function test_is_disputable_within_window() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);
        assertTrue(verifier.isDisputable(taskId));
    }

    function test_is_finalizable_after_window() public {
        uint256 taskId = _postAndClaim();
        vm.prank(alice);
        taskReg.submitProof(taskId, PROOF_HASH);

        assertFalse(verifier.isFinalizable(taskId));
        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);
        assertTrue(verifier.isFinalizable(taskId));
    }

    // ─── No-verifier path still works (regression) ────────────────────────────

    function test_task_registry_optimistic_path_without_verifier() public {
        // Deploy a fresh setup with no verifier wired
        AgentRegistry ar2  = new AgentRegistry(treasury);
        BountyEscrow  be2  = new BountyEscrow(treasury);
        TaskRegistry  tr2  = new TaskRegistry(address(ar2), address(be2), treasury);
        ar2.setVerifier(address(tr2));
        be2.setTaskRegistry(address(tr2));
        // Note: no tr2.setExecutionVerifier(...)

        vm.deal(poster, 10 ether);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        ar2.registerAgent{value: MIN_STAKE}("ipfs://alice");

        vm.prank(poster);
        uint256 taskId = tr2.postTask{value: TOTAL_VALUE}(
            SWAP_TAG, "", "", 0, block.timestamp + 1 days, 60
        );
        vm.prank(alice);
        tr2.claimTask{value: CLAIM_BOND}(taskId);
        vm.prank(alice);
        tr2.submitProof(taskId, PROOF_HASH); // optimistic: settles immediately

        TaskRegistry.Task memory t = tr2.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
    }
}
