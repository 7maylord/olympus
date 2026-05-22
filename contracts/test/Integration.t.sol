// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";
import "../src/BountyEscrow.sol";
import "../src/TaskRegistry.sol";
import "../src/SomniaAgentsAdapter.sol";
import "../src/ExecutionVerifier.sol";

/// @dev Mock Somnia compute layer — returns configurable price/health data per call index.
contract MockSomnia {
    bool public priceTriggered   = true;
    bool public healthTriggered  = true;

    function setPrice(bool triggered)  external { priceTriggered  = triggered; }
    function setHealth(bool triggered) external { healthTriggered = triggered; }

    function queryAPI(string calldata url, string calldata) external view returns (bytes memory) {
        // "https://api." is a 12-char common prefix; index 12 distinguishes the service:
        // "https://api.lending-protocol..." → urlBytes[12] == 'l'
        // "https://api.price-feed..."       → urlBytes[12] == 'p'
        bytes memory urlBytes = bytes(url);
        if (urlBytes.length > 12 && urlBytes[12] == "l") {
            return abi.encode(healthTriggered ? uint256(1.1e18) : uint256(2.0e18));
        }
        return abi.encode(priceTriggered ? uint256(1_900e18) : uint256(2_100e18));
    }
}

contract IntegrationTest is Test {
    AgentRegistry       agentReg;
    BountyEscrow        escrow;
    TaskRegistry        taskReg;
    SomniaAgentsAdapter adapter;
    ExecutionVerifier   verifier;
    MockSomnia          mockSomnia;

    address treasury = makeAddr("treasury");

    // 10 agent operators
    address[10] agents;

    uint256 constant AGENT_STAKE  = 0.05 ether;  // 10 claim slots each
    uint256 constant CLAIM_BOND   = 0.0001 ether;
    uint256 constant MIN_BOUNTY   = 0.001 ether;
    uint256 constant LISTING_FEE  = 0.0001 ether;
    uint256 constant TOTAL_VALUE  = MIN_BOUNTY + LISTING_FEE;

    bytes32 constant TAG_SWAP      = keccak256("SWAP");
    bytes32 constant TAG_GUARD     = keccak256("COLLATERAL_GUARD");
    bytes32 constant TAG_REBALANCE = keccak256("YIELD_REBALANCE");
    bytes32 constant TAG_TRANSFER  = keccak256("RECURRING_TRANSFER");

    function setUp() public {
        mockSomnia = new MockSomnia();
        agentReg   = new AgentRegistry(treasury);
        escrow     = new BountyEscrow(treasury);
        adapter    = new SomniaAgentsAdapter(address(mockSomnia), "https://api.price-feed.xyz/v1/");
        taskReg    = new TaskRegistry(address(agentReg), address(escrow), treasury);
        verifier   = new ExecutionVerifier(address(taskReg), address(agentReg), address(adapter));

        agentReg.setVerifier(address(taskReg));
        escrow.setTaskRegistry(address(taskReg));
        taskReg.setExecutionVerifier(address(verifier));

        // Fund and register 10 agents
        for (uint256 i = 0; i < 10; i++) {
            agents[i] = makeAddr(string(abi.encodePacked("agent", i)));
            vm.deal(agents[i], 10 ether);
            vm.prank(agents[i]);
            agentReg.registerAgent{value: AGENT_STAKE}(
                string(abi.encodePacked("ipfs://agent", i))
            );
        }

        vm.deal(address(this), 1000 ether);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _post(bytes32 tag, bytes memory trigger) internal returns (uint256) {
        return taskReg.postTask{value: TOTAL_VALUE}(
            tag, trigger, abi.encode("action"), 0, block.timestamp + 1 days, 60
        );
    }

    function _claim(address agent, uint256 taskId) internal {
        vm.prank(agent);
        taskReg.claimTask{value: CLAIM_BOND}(taskId);
    }

    function _submitAndFinalize(address agent, uint256 taskId) internal {
        vm.prank(agent);
        taskReg.submitProof(taskId, bytes32("txhash"));
        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);
        verifier.finalizeExecution(taskId);
    }

    function _priceTrigger() internal view returns (bytes memory) {
        return adapter.encodePriceTrigger(address(0xBEEF), 2_000e18, true);
    }

    function _healthTrigger() internal view returns (bytes memory) {
        return adapter.encodeHealthFactorTrigger(address(0xCAFE), address(0xDEAD), 1.3e18);
    }

    function _apyTrigger() internal view returns (bytes memory) {
        return adapter.encodeAPYSpreadTrigger("pool-a", "pool-b", 200);
    }

    function _blockTrigger() internal view returns (bytes memory) {
        return adapter.encodeBlockIntervalTrigger(block.number, 10);
    }

    // ─── Task type: Conditional Swap ─────────────────────────────────────────

    function test_task_type_conditional_swap_full_lifecycle() public {
        mockSomnia.setPrice(true); // price < threshold → triggered
        uint256 taskId = _post(TAG_SWAP, _priceTrigger());

        _claim(agents[0], taskId);
        _submitAndFinalize(agents[0], taskId);

        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
    }

    function test_task_type_conditional_swap_trigger_not_met_reverts() public {
        mockSomnia.setPrice(false); // price > threshold → not triggered
        uint256 taskId = _post(TAG_SWAP, _priceTrigger());
        _claim(agents[0], taskId);

        vm.prank(agents[0]);
        vm.expectRevert(ExecutionVerifier.TriggerConditionNotMet.selector);
        taskReg.submitProof(taskId, bytes32("txhash"));
    }

    // ─── Task type: Collateral Guard ─────────────────────────────────────────

    function test_task_type_collateral_guard_full_lifecycle() public {
        mockSomnia.setHealth(true); // HF = 1.1 < 1.3 → triggered
        uint256 taskId = _post(TAG_GUARD, _healthTrigger());

        _claim(agents[1], taskId);
        _submitAndFinalize(agents[1], taskId);

        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
    }

    // ─── Task type: Yield Rebalancer ──────────────────────────────────────────

    function test_task_type_yield_rebalancer_full_lifecycle() public {
        // APY spread trigger needs real mock responses set up
        // Use no trigger condition for this test (pure execution test)
        uint256 taskId = _post(TAG_REBALANCE, "");
        _claim(agents[2], taskId);
        _submitAndFinalize(agents[2], taskId);

        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
    }

    // ─── Task type: Recurring Transfer ───────────────────────────────────────

    function test_task_type_recurring_transfer_block_interval() public {
        // anchor = current block, interval = 10 → triggers at block+10, block+20, ...
        uint256 anchor = block.number;
        bytes memory trigger = adapter.encodeBlockIntervalTrigger(anchor, 10);
        uint256 taskId = _post(TAG_TRANSFER, trigger);

        _claim(agents[3], taskId);

        // Advance 10 blocks so interval trigger fires
        vm.roll(anchor + 10);
        _submitAndFinalize(agents[3], taskId);

        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
    }

    // ─── 10-agent claim race: exactly one winner ──────────────────────────────

    function test_claim_race_exactly_one_winner() public {
        uint256 taskId = _post(TAG_SWAP, "");

        // Agent 0 wins the race
        _claim(agents[0], taskId);

        // All other agents fail
        for (uint256 i = 1; i < 10; i++) {
            vm.prank(agents[i]);
            vm.expectRevert(TaskRegistry.TaskNotOpen.selector);
            taskReg.claimTask{value: CLAIM_BOND}(taskId);
        }

        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(t.claimedBy, agents[0]);
    }

    // ─── Concurrent claim cap ─────────────────────────────────────────────────

    function test_concurrent_claim_cap_enforced() public {
        // AGENT_STAKE = 0.05 ether / STAKE_PER_SLOT = 0.005 ether → 10 slots
        uint256 agentId = agentRegistry().agentOf(agents[0]);
        assertEq(agentReg.maxConcurrentClaims(agentId), 10);

        // Post and claim 10 tasks — all succeed
        uint256[] memory taskIds = new uint256[](11);
        for (uint256 i = 0; i < 11; i++) {
            taskIds[i] = _post(TAG_SWAP, "");
        }
        for (uint256 i = 0; i < 10; i++) {
            _claim(agents[0], taskIds[i]);
        }

        // 11th claim hits the cap
        vm.prank(agents[0]);
        vm.expectRevert(TaskRegistry.ClaimLimitReached.selector);
        taskReg.claimTask{value: CLAIM_BOND}(taskIds[10]);
    }

    // ─── Claim expire → re-open → re-claim ────────────────────────────────────

    function test_expired_claim_reopens_for_second_agent() public {
        uint256 taskId = _post(TAG_SWAP, "");

        // Agent 0 claims but window expires
        _claim(agents[0], taskId);
        vm.warp(block.timestamp + 61);
        taskReg.expireTask(taskId);

        // Agent 1 picks it up
        _claim(agents[1], taskId);
        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(t.claimedBy, agents[1]);
    }

    function test_expired_claim_forfeits_bond_and_triggers_miss() public {
        uint256 agentId = agentReg.agentOf(agents[0]);
        (uint256 repBefore,) = agentReg.getFeedback(agentId);

        uint256 taskId = _post(TAG_SWAP, "");
        _claim(agents[0], taskId);

        uint256 treasuryBefore = treasury.balance;
        vm.warp(block.timestamp + 61);
        taskReg.expireTask(taskId);

        // Bond forfeited
        assertEq(treasury.balance, treasuryBefore + CLAIM_BOND);
        // Reputation penalised
        (uint256 repAfter,) = agentReg.getFeedback(agentId);
        assertLt(repAfter, repBefore);
    }

    // ─── Dispute resolution ────────────────────────────────────────────────────

    function test_dispute_success_slashes_agent_and_refunds_poster() public {
        address poster = makeAddr("poster");
        vm.deal(poster, 10 ether);

        // Pre-compute trigger bytes before vm.prank — _priceTrigger() calls an external
        // contract (adapter), which would otherwise consume the prank before postTask.
        bytes memory trigger = _priceTrigger();
        mockSomnia.setPrice(true);
        vm.prank(poster);
        uint256 taskId = taskReg.postTask{value: TOTAL_VALUE}(
            TAG_SWAP, trigger, "", 0, block.timestamp + 1 days, 60
        );

        _claim(agents[0], taskId);

        vm.prank(agents[0]);
        taskReg.submitProof(taskId, bytes32("bad_proof"));

        // Condition no longer holds when poster disputes
        mockSomnia.setPrice(false);
        uint256 posterBefore = poster.balance;

        vm.prank(poster);
        verifier.disputeExecution(taskId);

        // Poster recovered their bounty
        assertGt(poster.balance, posterBefore);
        // Treasury received claim bond
        assertGt(treasury.balance, 0);
        // Task is Disputed
        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Disputed));
    }

    function test_dispute_fail_confirms_agent_payout() public {
        address poster = makeAddr("poster2");
        vm.deal(poster, 10 ether);

        bytes memory trigger = _priceTrigger(); // pre-compute before prank
        mockSomnia.setPrice(true);
        vm.prank(poster);
        uint256 taskId = taskReg.postTask{value: TOTAL_VALUE}(
            TAG_SWAP, trigger, "", 0, block.timestamp + 1 days, 60
        );

        _claim(agents[0], taskId);
        vm.prank(agents[0]);
        taskReg.submitProof(taskId, bytes32("txhash"));

        uint256 agentBefore = agents[0].balance;

        // Poster disputes but condition still holds → dispute fails
        vm.prank(poster);
        verifier.disputeExecution(taskId);

        // Agent got paid
        assertGt(agents[0].balance, agentBefore);
        TaskRegistry.Task memory t = taskReg.getTask(taskId);
        assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
    }

    // ─── 100-task throughput ──────────────────────────────────────────────────

    function test_100_tasks_all_executed() public {
        uint256[] memory taskIds = new uint256[](100);

        // Post 100 tasks distributed across all 4 types
        bytes32[4] memory tags = [TAG_SWAP, TAG_GUARD, TAG_REBALANCE, TAG_TRANSFER];
        for (uint256 i = 0; i < 100; i++) {
            taskIds[i] = _post(tags[i % 4], "");
        }

        // Distribute across 10 agents (10 tasks each, within their 10-slot cap)
        for (uint256 i = 0; i < 100; i++) {
            _claim(agents[i % 10], taskIds[i]);
        }

        // Submit and finalize all
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(agents[i % 10]);
            taskReg.submitProof(taskIds[i], bytes32(i + 1));
        }
        vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);
        for (uint256 i = 0; i < 100; i++) {
            verifier.finalizeExecution(taskIds[i]);
        }

        // Verify all 100 executed
        for (uint256 i = 0; i < 100; i++) {
            TaskRegistry.Task memory t = taskReg.getTask(taskIds[i]);
            assertEq(uint8(t.status), uint8(TaskRegistry.TaskStatus.Executed));
        }

        assertEq(taskReg.taskCount(), 100);
    }

    // ─── Reputation builds over many tasks ────────────────────────────────────

    function test_agent_reputation_improves_with_successes() public {
        uint256 agentId = agentReg.agentOf(agents[0]);
        (uint256 repBefore,) = agentReg.getFeedback(agentId);

        // Agent has 10 claim slots — process 20 tasks in two batches of 10
        // to avoid ClaimLimitReached (active claims only free on finalization).
        uint256 taskBase = taskReg.taskCount();
        for (uint256 batch = 0; batch < 2; batch++) {
            uint256[] memory batchIds = new uint256[](10);
            for (uint256 i = 0; i < 10; i++) {
                batchIds[i] = _post(TAG_SWAP, "");
                _claim(agents[0], batchIds[i]);
                vm.prank(agents[0]);
                taskReg.submitProof(batchIds[i], bytes32(taskBase + batch * 10 + i + 1));
            }
            vm.warp(block.timestamp + verifier.DISPUTE_WINDOW() + 1);
            for (uint256 i = 0; i < 10; i++) {
                verifier.finalizeExecution(batchIds[i]);
            }
        }

        (uint256 repAfter, uint256 total) = agentReg.getFeedback(agentId);
        assertGt(repAfter, repBefore);
        assertEq(total, 20);
    }

    // ─── Reputation gate blocks low-rep agent ─────────────────────────────────

    function test_reputation_gate_blocks_low_rep_agent() public {
        // Post task requiring high reputation
        uint256 taskId = taskReg.postTask{value: TOTAL_VALUE}(
            TAG_SWAP, "", "", 800, block.timestamp + 1 days, 60
        );

        // New agent has default rep = 500 → blocked
        vm.prank(agents[9]);
        vm.expectRevert(TaskRegistry.InsufficientReputation.selector);
        taskReg.claimTask{value: CLAIM_BOND}(taskId);
    }

    // ─── Miss streak leads to auto-deregister ─────────────────────────────────

    function test_three_misses_auto_deregisters_agent() public {
        uint256 agentId = agentReg.agentOf(agents[0]);

        for (uint256 i = 0; i < 3; i++) {
            uint256 taskId = _post(TAG_SWAP, "");
            _claim(agents[0], taskId);
            vm.warp(block.timestamp + 61); // let claim window expire
            taskReg.expireTask(taskId);
        }

        (,,,,,,,,bool active) = agentReg.agentData(agentId);
        assertFalse(active);
    }

    // ─── Open task expiry refunds poster ──────────────────────────────────────

    function test_open_task_expiry_full_refund() public {
        address poster = makeAddr("poster3");
        vm.deal(poster, 10 ether);
        uint256 posterBefore = poster.balance - TOTAL_VALUE;

        vm.prank(poster);
        uint256 taskId = taskReg.postTask{value: TOTAL_VALUE}(
            TAG_SWAP, "", "", 0, block.timestamp + 1 days, 60
        );

        vm.warp(block.timestamp + 2 days);
        taskReg.expireTask(taskId);

        // Poster gets MIN_BOUNTY back (listing fee is non-refundable)
        assertEq(poster.balance, posterBefore + TOTAL_VALUE - LISTING_FEE);
    }

    // ─── Internal helper (avoids stack-too-deep in large tests) ──────────────

    function agentRegistry() internal view returns (AgentRegistry) { return agentReg; }
}
