// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SomniaAgentsAdapter.sol";

/// @dev Mock ISomniaAgents — calls onAgentResponse synchronously within createTask
///      so tests stay single-transaction. Keyed by keccak256(trigger bytes).
contract MockSomniaAgents {
    SomniaAgentsAdapter public adapter;
    mapping(bytes32 => bytes) private _results; // keccak256(trigger) => encoded result
    uint256 public nextId;

    function setAdapter(address a) external { adapter = SomniaAgentsAdapter(a); }

    /// @dev taskData = abi.encode(trigger, priceFeedBase) as encoded by requestOracleUpdate.
    function setResult(bytes calldata trigger, bytes calldata result) external {
        _results[keccak256(trigger)] = result;
    }

    function createTask(uint256, bytes calldata taskData) external payable returns (uint256 id) {
        id = ++nextId;
        (bytes memory trigger,) = abi.decode(taskData, (bytes, string));
        adapter.onAgentResponse(id, taskData, _results[keccak256(trigger)]);
    }
}

contract SomniaAgentsAdapterTest is Test {
    SomniaAgentsAdapter adapter;
    MockSomniaAgents    mock;

    address constant TOKEN    = address(0xBEEF);
    address constant PROTOCOL = address(0xCAFE);
    address constant USER     = address(0xDEAD);

    string constant PRICE_BASE = "https://api.price-feed.xyz/v1/";
    string constant POOL_A     = "pool-a-id";
    string constant POOL_B     = "pool-b-id";

    function setUp() public {
        mock    = new MockSomniaAgents();
        adapter = new SomniaAgentsAdapter(address(mock), PRICE_BASE);
        mock.setAdapter(address(adapter));
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _primePrice(address token, uint256 threshold, bool triggerBelow, uint256 price)
        internal returns (bytes memory trigger)
    {
        trigger = adapter.encodePriceTrigger(token, threshold, triggerBelow);
        mock.setResult(trigger, abi.encode(price));
        adapter.requestOracleUpdate(trigger);
    }

    function _primeHF(address protocol, address user, uint256 minHF, uint256 actualHF)
        internal returns (bytes memory trigger)
    {
        trigger = adapter.encodeHealthFactorTrigger(protocol, user, minHF);
        mock.setResult(trigger, abi.encode(actualHF));
        adapter.requestOracleUpdate(trigger);
    }

    function _primeAPY(string memory poolA, string memory poolB, uint256 minSpread, uint256 apyA, uint256 apyB)
        internal returns (bytes memory trigger)
    {
        trigger = adapter.encodeAPYSpreadTrigger(poolA, poolB, minSpread);
        mock.setResult(trigger, abi.encode(apyA, apyB));
        adapter.requestOracleUpdate(trigger);
    }

    // ─── Price triggers ───────────────────────────────────────────────────────

    function test_price_below_triggers_when_price_under_threshold() public {
        bytes memory t = _primePrice(TOKEN, 2_000e18, true, 1_900e18);
        assertTrue(adapter.evaluate(t));
    }

    function test_price_below_does_not_trigger_when_price_above() public {
        bytes memory t = _primePrice(TOKEN, 2_000e18, true, 2_100e18);
        assertFalse(adapter.evaluate(t));
    }

    function test_price_above_triggers_when_price_over_threshold() public {
        bytes memory t = _primePrice(TOKEN, 3_000e18, false, 3_500e18);
        assertTrue(adapter.evaluate(t));
    }

    function test_price_above_does_not_trigger_when_price_below() public {
        bytes memory t = _primePrice(TOKEN, 3_000e18, false, 2_500e18);
        assertFalse(adapter.evaluate(t));
    }

    function test_price_at_threshold_boundary_not_triggered() public {
        bytes memory t = _primePrice(TOKEN, 2_000e18, true, 2_000e18);
        assertFalse(adapter.evaluate(t)); // strictly less-than
    }

    function test_empty_oracle_response_not_triggered() public {
        bytes memory trigger = adapter.encodePriceTrigger(TOKEN, 2_000e18, true);
        // No setResult call — mock returns empty bytes by default
        adapter.requestOracleUpdate(trigger);
        assertFalse(adapter.evaluate(trigger));
    }

    function test_price_trigger_reverts_zero_address_token() public {
        bytes memory trigger = adapter.encodePriceTrigger(address(0), 2_000e18, true);
        vm.expectRevert(SomniaAgentsAdapter.InvalidParams.selector);
        adapter.requestOracleUpdate(trigger);
    }

    // ─── Health factor trigger ────────────────────────────────────────────────

    function test_health_factor_triggers_when_below_min() public {
        bytes memory t = _primeHF(PROTOCOL, USER, 1.3e18, 1.1e18);
        assertTrue(adapter.evaluate(t));
    }

    function test_health_factor_does_not_trigger_when_above_min() public {
        bytes memory t = _primeHF(PROTOCOL, USER, 1.3e18, 1.5e18);
        assertFalse(adapter.evaluate(t));
    }

    function test_health_factor_empty_response_not_triggered() public {
        bytes memory trigger = adapter.encodeHealthFactorTrigger(PROTOCOL, USER, 1.3e18);
        adapter.requestOracleUpdate(trigger);
        assertFalse(adapter.evaluate(trigger));
    }

    function test_health_factor_reverts_zero_address() public {
        bytes memory trigger = adapter.encodeHealthFactorTrigger(address(0), USER, 1.3e18);
        vm.expectRevert(SomniaAgentsAdapter.InvalidParams.selector);
        adapter.requestOracleUpdate(trigger);
    }

    // ─── APY spread trigger ───────────────────────────────────────────────────

    function test_apy_spread_triggers_when_spread_exceeds_threshold() public {
        bytes memory t = _primeAPY(POOL_A, POOL_B, 200, 800, 500); // 300 BPS spread
        assertTrue(adapter.evaluate(t));
    }

    function test_apy_spread_does_not_trigger_when_below_threshold() public {
        bytes memory t = _primeAPY(POOL_A, POOL_B, 200, 520, 500); // 20 BPS spread
        assertFalse(adapter.evaluate(t));
    }

    function test_apy_spread_works_regardless_of_pool_order() public {
        bytes memory t = _primeAPY(POOL_A, POOL_B, 200, 500, 800); // B > A, spread still 300
        assertTrue(adapter.evaluate(t));
    }

    function test_apy_spread_empty_response_not_triggered() public {
        bytes memory trigger = adapter.encodeAPYSpreadTrigger(POOL_A, POOL_B, 200);
        adapter.requestOracleUpdate(trigger);
        assertFalse(adapter.evaluate(trigger));
    }

    // ─── Block interval trigger ───────────────────────────────────────────────

    function test_block_interval_triggers_on_exact_multiple() public {
        vm.roll(1000);
        bytes memory t = adapter.encodeBlockIntervalTrigger(0, 100);
        adapter.requestOracleUpdate(t);
        assertTrue(adapter.evaluate(t));
    }

    function test_block_interval_does_not_trigger_between_multiples() public {
        vm.roll(1050);
        bytes memory t = adapter.encodeBlockIntervalTrigger(0, 100);
        adapter.requestOracleUpdate(t);
        assertFalse(adapter.evaluate(t));
    }

    function test_block_interval_uses_anchor_block() public {
        vm.roll(1100);
        bytes memory t = adapter.encodeBlockIntervalTrigger(100, 100);
        adapter.requestOracleUpdate(t);
        assertTrue(adapter.evaluate(t));
    }

    function test_block_interval_does_not_trigger_at_anchor() public {
        vm.roll(100);
        bytes memory t = adapter.encodeBlockIntervalTrigger(100, 100);
        adapter.requestOracleUpdate(t);
        assertFalse(adapter.evaluate(t));
    }

    function test_block_interval_reverts_zero_interval() public {
        bytes memory t = adapter.encodeBlockIntervalTrigger(0, 0);
        vm.expectRevert(SomniaAgentsAdapter.InvalidParams.selector);
        adapter.requestOracleUpdate(t);
    }

    // ─── Cache staleness ──────────────────────────────────────────────────────

    function test_evaluate_reverts_when_no_cache() public {
        bytes memory t = adapter.encodePriceTrigger(TOKEN, 2_000e18, true);
        vm.expectRevert(SomniaAgentsAdapter.OracleResultStale.selector);
        adapter.evaluate(t);
    }

    function test_evaluate_reverts_when_cache_expired() public {
        bytes memory t = _primePrice(TOKEN, 2_000e18, true, 1_900e18);
        vm.roll(block.number + adapter.CACHE_VALID_BLOCKS() + 1);
        vm.expectRevert(SomniaAgentsAdapter.OracleResultStale.selector);
        adapter.evaluate(t);
    }

    function test_evaluate_succeeds_at_last_valid_block() public {
        bytes memory t = _primePrice(TOKEN, 2_000e18, true, 1_900e18);
        vm.roll(block.number + adapter.CACHE_VALID_BLOCKS());
        assertTrue(adapter.evaluate(t)); // exactly at boundary — still valid
    }

    // ─── Encoding helpers (pure — no mock needed) ─────────────────────────────

    function test_encode_decode_price_trigger_roundtrip() public view {
        bytes memory encoded = adapter.encodePriceTrigger(TOKEN, 2_000e18, true);
        SomniaAgentsAdapter.TriggerCondition memory cond =
            abi.decode(encoded, (SomniaAgentsAdapter.TriggerCondition));
        assertEq(uint8(cond.triggerType), uint8(SomniaAgentsAdapter.TriggerType.PriceBelow));
        (address tok, uint256 thresh) = abi.decode(cond.params, (address, uint256));
        assertEq(tok,    TOKEN);
        assertEq(thresh, 2_000e18);
    }

    function test_encode_decode_health_factor_roundtrip() public view {
        bytes memory encoded = adapter.encodeHealthFactorTrigger(PROTOCOL, USER, 1.3e18);
        SomniaAgentsAdapter.TriggerCondition memory cond =
            abi.decode(encoded, (SomniaAgentsAdapter.TriggerCondition));
        assertEq(uint8(cond.triggerType), uint8(SomniaAgentsAdapter.TriggerType.HealthFactor));
        (address p, address u, uint256 minHF) = abi.decode(cond.params, (address, address, uint256));
        assertEq(p,    PROTOCOL);
        assertEq(u,    USER);
        assertEq(minHF, 1.3e18);
    }

    function test_encode_decode_block_interval_roundtrip() public view {
        bytes memory encoded = adapter.encodeBlockIntervalTrigger(500, 200);
        SomniaAgentsAdapter.TriggerCondition memory cond =
            abi.decode(encoded, (SomniaAgentsAdapter.TriggerCondition));
        assertEq(uint8(cond.triggerType), uint8(SomniaAgentsAdapter.TriggerType.BlockInterval));
        (uint256 anchor, uint256 interval) = abi.decode(cond.params, (uint256, uint256));
        assertEq(anchor,   500);
        assertEq(interval, 200);
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_price_below_trigger(uint256 price, uint256 threshold) public {
        vm.assume(price > 0 && price < type(uint128).max);
        vm.assume(threshold > 0 && threshold < type(uint128).max);

        bytes memory trigger = adapter.encodePriceTrigger(TOKEN, threshold, true);
        mock.setResult(trigger, abi.encode(price));
        adapter.requestOracleUpdate(trigger);

        assertEq(adapter.evaluate(trigger), price < threshold);
    }

    function testFuzz_block_interval_trigger(uint256 anchor, uint256 interval, uint256 currentBlock) public {
        interval     = bound(interval, 1, 1000);
        anchor       = bound(anchor, 0, 1_000_000);
        currentBlock = bound(currentBlock, anchor + 1, anchor + interval * 100);

        vm.roll(currentBlock);
        bytes memory t = adapter.encodeBlockIntervalTrigger(anchor, interval);
        adapter.requestOracleUpdate(t);
        assertEq(adapter.evaluate(t), (currentBlock - anchor) % interval == 0);
    }
}
