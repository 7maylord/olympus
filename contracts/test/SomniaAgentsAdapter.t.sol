// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SomniaAgentsAdapter.sol";

/// @dev Mock ISomniaAgents that returns pre-programmed values per URL key.
contract MockSomniaAgents {
    mapping(bytes32 => bytes) private _responses;

    function setResponse(string calldata url, bytes calldata value) external {
        _responses[keccak256(bytes(url))] = value;
    }

    function queryAPI(string calldata url, string calldata) external view returns (bytes memory) {
        return _responses[keccak256(bytes(url))];
    }
}

contract SomniaAgentsAdapterTest is Test {
    SomniaAgentsAdapter adapter;
    MockSomniaAgents    mock;

    address constant TOKEN       = address(0xBEEF);
    address constant PROTOCOL    = address(0xCAFE);
    address constant USER        = address(0xDEAD);

    string constant PRICE_BASE   = "https://api.price-feed.xyz/v1/";
    string constant POOL_A       = "pool-a-id";
    string constant POOL_B       = "pool-b-id";

    function setUp() public {
        mock    = new MockSomniaAgents();
        adapter = new SomniaAgentsAdapter(address(mock), PRICE_BASE);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _priceUrl(address token) internal pure returns (string memory) {
        // Reproduce the adapter's _toHexString output
        bytes memory buf = new bytes(42);
        buf[0] = "0"; buf[1] = "x";
        bytes memory hex_chars = "0123456789abcdef";
        uint160 v = uint160(token);
        for (uint256 i = 41; i >= 2; i--) {
            buf[i] = hex_chars[v & 0xf];
            v >>= 4;
        }
        return string(abi.encodePacked(PRICE_BASE, string(buf)));
    }

    function _setPrice(address token, uint256 price) internal {
        mock.setResponse(_priceUrl(token), abi.encode(price));
    }

    // ─── Price triggers ───────────────────────────────────────────────────────

    function test_price_below_triggers_when_price_under_threshold() public {
        _setPrice(TOKEN, 1_900e18); // $1,900

        bytes memory encoded = adapter.encodePriceTrigger(TOKEN, 2_000e18, true);
        bool triggered = adapter.evaluate(encoded);
        assertTrue(triggered);
    }

    function test_price_below_does_not_trigger_when_price_above() public {
        _setPrice(TOKEN, 2_100e18); // $2,100

        bytes memory encoded = adapter.encodePriceTrigger(TOKEN, 2_000e18, true);
        bool triggered = adapter.evaluate(encoded);
        assertFalse(triggered);
    }

    function test_price_above_triggers_when_price_over_threshold() public {
        _setPrice(TOKEN, 3_500e18);

        bytes memory encoded = adapter.encodePriceTrigger(TOKEN, 3_000e18, false);
        bool triggered = adapter.evaluate(encoded);
        assertTrue(triggered);
    }

    function test_price_above_does_not_trigger_when_price_below() public {
        _setPrice(TOKEN, 2_500e18);

        bytes memory encoded = adapter.encodePriceTrigger(TOKEN, 3_000e18, false);
        bool triggered = adapter.evaluate(encoded);
        assertFalse(triggered);
    }

    function test_price_at_threshold_boundary_below() public {
        _setPrice(TOKEN, 2_000e18); // exactly at threshold

        bytes memory encoded = adapter.encodePriceTrigger(TOKEN, 2_000e18, true);
        bool triggered = adapter.evaluate(encoded);
        assertFalse(triggered); // strictly less-than
    }

    function test_evaluate_price_trigger_convenience_wrapper() public {
        _setPrice(TOKEN, 1_500e18);
        bool triggered = adapter.evaluatePriceTrigger(TOKEN, 2_000e18, true);
        assertTrue(triggered);
    }

    function test_price_feed_failed_reverts_on_empty_response() public {
        // No response set — mock returns empty bytes
        bytes memory encoded = adapter.encodePriceTrigger(TOKEN, 2_000e18, true);
        vm.expectRevert(SomniaAgentsAdapter.PriceFeedFailed.selector);
        adapter.evaluate(encoded);
    }

    function test_price_trigger_reverts_zero_address_token() public {
        SomniaAgentsAdapter.TriggerCondition memory cond = SomniaAgentsAdapter.TriggerCondition({
            triggerType: SomniaAgentsAdapter.TriggerType.PriceBelow,
            params: abi.encode(address(0), uint256(1_000e18))
        });
        vm.expectRevert(SomniaAgentsAdapter.InvalidParams.selector);
        adapter.evaluate(abi.encode(cond));
    }

    // ─── Health factor trigger ────────────────────────────────────────────────

    function _setHealthFactor(address protocol, address user, uint256 hf) internal {
        bytes memory buf_p = new bytes(42);
        bytes memory buf_u = new bytes(42);
        bytes memory hex_chars = "0123456789abcdef";
        buf_p[0] = "0"; buf_p[1] = "x";
        buf_u[0] = "0"; buf_u[1] = "x";
        uint160 vp = uint160(protocol);
        uint160 vu = uint160(user);
        for (uint256 i = 41; i >= 2; i--) {
            buf_p[i] = hex_chars[vp & 0xf]; vp >>= 4;
            buf_u[i] = hex_chars[vu & 0xf]; vu >>= 4;
        }
        string memory url = string(abi.encodePacked(
            "https://api.lending-protocol.xyz/v1/health/",
            string(buf_p), "/", string(buf_u)
        ));
        mock.setResponse(url, abi.encode(hf));
    }

    function test_health_factor_triggers_when_below_min() public {
        _setHealthFactor(PROTOCOL, USER, 1.1e18); // HF = 1.1

        bytes memory encoded = adapter.encodeHealthFactorTrigger(PROTOCOL, USER, 1.3e18);
        bool triggered = adapter.evaluate(encoded);
        assertTrue(triggered);
    }

    function test_health_factor_does_not_trigger_when_above_min() public {
        _setHealthFactor(PROTOCOL, USER, 1.5e18);

        bytes memory encoded = adapter.encodeHealthFactorTrigger(PROTOCOL, USER, 1.3e18);
        bool triggered = adapter.evaluate(encoded);
        assertFalse(triggered);
    }

    function test_health_factor_reverts_on_empty_response() public {
        bytes memory encoded = adapter.encodeHealthFactorTrigger(PROTOCOL, USER, 1.3e18);
        vm.expectRevert(SomniaAgentsAdapter.HealthFactorFailed.selector);
        adapter.evaluate(encoded);
    }

    function test_health_factor_reverts_zero_address() public {
        SomniaAgentsAdapter.TriggerCondition memory cond = SomniaAgentsAdapter.TriggerCondition({
            triggerType: SomniaAgentsAdapter.TriggerType.HealthFactor,
            params: abi.encode(address(0), USER, uint256(1.3e18))
        });
        vm.expectRevert(SomniaAgentsAdapter.InvalidParams.selector);
        adapter.evaluate(abi.encode(cond));
    }

    // ─── APY spread trigger ───────────────────────────────────────────────────

    function _setAPY(string memory pool, uint256 apyBPS) internal {
        string memory url = string(abi.encodePacked("https://api.defi-yields.xyz/v1/pool/", pool));
        mock.setResponse(url, abi.encode(apyBPS));
    }

    function test_apy_spread_triggers_when_spread_exceeds_threshold() public {
        _setAPY(POOL_A, 800);  // 8%
        _setAPY(POOL_B, 500);  // 5% → spread = 300 BPS

        bytes memory encoded = adapter.encodeAPYSpreadTrigger(POOL_A, POOL_B, 200);
        bool triggered = adapter.evaluate(encoded);
        assertTrue(triggered);
    }

    function test_apy_spread_does_not_trigger_when_below_threshold() public {
        _setAPY(POOL_A, 520);
        _setAPY(POOL_B, 500); // spread = 20 BPS

        bytes memory encoded = adapter.encodeAPYSpreadTrigger(POOL_A, POOL_B, 200);
        bool triggered = adapter.evaluate(encoded);
        assertFalse(triggered);
    }

    function test_apy_spread_works_regardless_of_pool_order() public {
        _setAPY(POOL_A, 500);
        _setAPY(POOL_B, 800); // B > A — spread still 300 BPS

        bytes memory encoded = adapter.encodeAPYSpreadTrigger(POOL_A, POOL_B, 200);
        bool triggered = adapter.evaluate(encoded);
        assertTrue(triggered);
    }

    function test_apy_spread_reverts_on_missing_pool() public {
        _setAPY(POOL_A, 800);
        // POOL_B not set

        bytes memory encoded = adapter.encodeAPYSpreadTrigger(POOL_A, POOL_B, 200);
        vm.expectRevert(SomniaAgentsAdapter.APYFetchFailed.selector);
        adapter.evaluate(encoded);
    }

    // ─── Block interval trigger ───────────────────────────────────────────────

    function test_block_interval_triggers_on_exact_multiple() public {
        vm.roll(1000); // current block
        bytes memory encoded = adapter.encodeBlockIntervalTrigger(0, 100);
        bool triggered = adapter.evaluate(encoded);
        assertTrue(triggered); // 1000 % 100 == 0 and 1000 > 0
    }

    function test_block_interval_does_not_trigger_between_multiples() public {
        vm.roll(1050);
        bytes memory encoded = adapter.encodeBlockIntervalTrigger(0, 100);
        bool triggered = adapter.evaluate(encoded);
        assertFalse(triggered); // 1050 % 100 != 0
    }

    function test_block_interval_uses_anchor_block() public {
        vm.roll(1100);
        bytes memory encoded = adapter.encodeBlockIntervalTrigger(100, 100);
        bool triggered = adapter.evaluate(encoded);
        assertTrue(triggered); // (1100 - 100) % 100 == 0
    }

    function test_block_interval_does_not_trigger_at_anchor() public {
        vm.roll(100);
        bytes memory encoded = adapter.encodeBlockIntervalTrigger(100, 100);
        bool triggered = adapter.evaluate(encoded);
        assertFalse(triggered); // block.number == anchorBlock, not > anchorBlock
    }

    function test_block_interval_reverts_zero_interval() public {
        bytes memory encoded = adapter.encodeBlockIntervalTrigger(0, 0);
        vm.expectRevert(SomniaAgentsAdapter.InvalidParams.selector);
        adapter.evaluate(encoded);
    }

    // ─── Unsupported trigger type ─────────────────────────────────────────────

    function test_unsupported_trigger_type_reverts() public {
        // Craft a raw TriggerCondition with an out-of-range type value (5)
        bytes memory encoded = abi.encode(uint8(5), bytes(""));
        vm.expectRevert();
        adapter.evaluate(encoded);
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
        _setPrice(TOKEN, price);

        bytes memory encoded = adapter.encodePriceTrigger(TOKEN, threshold, true);
        bool triggered = adapter.evaluate(encoded);
        assertEq(triggered, price < threshold);
    }

    function testFuzz_block_interval_trigger(uint256 anchor, uint256 interval, uint256 currentBlock) public {
        interval     = bound(interval, 1, 1000);
        anchor       = bound(anchor, 0, 1_000_000);
        currentBlock = bound(currentBlock, anchor + 1, anchor + interval * 100);

        vm.roll(currentBlock);
        bytes memory encoded = adapter.encodeBlockIntervalTrigger(anchor, interval);
        bool triggered = adapter.evaluate(encoded);
        assertEq(triggered, (currentBlock - anchor) % interval == 0);
    }
}
