// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Somnia's native on-chain AI compute interface.
/// Contracts can query external APIs and run deterministic models inside transactions.
interface ISomniaAgents {
    function queryAPI(string calldata url, string calldata jsonPath) external returns (bytes memory result);
}

/// @notice Trigger-condition evaluator that calls Somnia Agents inside transactions,
/// eliminating off-chain price monitors and oracles entirely.
contract SomniaAgentsAdapter {
    // ─── Types ───────────────────────────────────────────────────────────────

    enum TriggerType {
        PriceBelow,    // token spot price drops under threshold
        PriceAbove,    // token spot price rises above threshold
        HealthFactor,  // lending position health factor drops below threshold
        APYSpread,     // yield spread between two pools exceeds threshold
        BlockInterval  // N blocks have elapsed since anchor block
    }

    struct TriggerCondition {
        TriggerType triggerType;
        bytes       params;          // ABI-encoded per TriggerType (see evaluate*)
    }

    // ─── Storage ─────────────────────────────────────────────────────────────

    ISomniaAgents public immutable somniaAgents;

    // Base URL for price feed API — configurable so testnet can point elsewhere
    string public priceFeedBase;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error UnsupportedTriggerType();
    error InvalidParams();
    error PriceFeedFailed();
    error HealthFactorFailed();
    error APYFetchFailed();

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _somniaAgents, string memory _priceFeedBase) {
        somniaAgents  = ISomniaAgents(_somniaAgents);
        priceFeedBase = _priceFeedBase;
    }

    // ─── Primary entry point ─────────────────────────────────────────────────

    /// @notice Evaluate any trigger condition. Called inside a transaction by ExecutionVerifier
    ///         or directly by agents polling on-chain before executing.
    /// @param encoded ABI-encoded TriggerCondition struct
    /// @return triggered True if the condition is currently satisfied
    function evaluate(bytes calldata encoded) external returns (bool triggered) {
        TriggerCondition memory cond = abi.decode(encoded, (TriggerCondition));

        if (cond.triggerType == TriggerType.PriceBelow || cond.triggerType == TriggerType.PriceAbove) {
            return _evaluatePrice(cond);
        } else if (cond.triggerType == TriggerType.HealthFactor) {
            return _evaluateHealthFactor(cond);
        } else if (cond.triggerType == TriggerType.APYSpread) {
            return _evaluateAPYSpread(cond);
        } else if (cond.triggerType == TriggerType.BlockInterval) {
            return _evaluateBlockInterval(cond);
        } else {
            revert UnsupportedTriggerType();
        }
    }

    // ─── Price trigger ───────────────────────────────────────────────────────

    /// Params: (address token, uint256 thresholdUSD_18dec)
    function _evaluatePrice(TriggerCondition memory cond) internal returns (bool) {
        (address token, uint256 thresholdUSD) = abi.decode(cond.params, (address, uint256));
        if (token == address(0)) revert InvalidParams();

        bytes memory raw = somniaAgents.queryAPI(
            string(abi.encodePacked(priceFeedBase, _toHexString(token))),
            "$.price_usd"
        );
        if (raw.length == 0) revert PriceFeedFailed();

        uint256 currentPrice = abi.decode(raw, (uint256));

        return cond.triggerType == TriggerType.PriceBelow
            ? currentPrice < thresholdUSD
            : currentPrice > thresholdUSD;
    }

    /// @notice Convenience wrapper used by ExecutionVerifier for the conditional-swap task type.
    function evaluatePriceTrigger(address token, uint256 thresholdUSD, bool triggerBelow)
        external
        returns (bool triggered)
    {
        bytes memory raw = somniaAgents.queryAPI(
            string(abi.encodePacked(priceFeedBase, _toHexString(token))),
            "$.price_usd"
        );
        if (raw.length == 0) revert PriceFeedFailed();
        uint256 currentPrice = abi.decode(raw, (uint256));
        triggered = triggerBelow ? currentPrice < thresholdUSD : currentPrice > thresholdUSD;
    }

    // ─── Health factor trigger ────────────────────────────────────────────────

    /// Params: (address lendingProtocol, address user, uint256 minHealthFactor_18dec)
    function _evaluateHealthFactor(TriggerCondition memory cond) internal returns (bool) {
        (address protocol, address user, uint256 minHF) = abi.decode(cond.params, (address, address, uint256));
        if (protocol == address(0) || user == address(0)) revert InvalidParams();

        bytes memory raw = somniaAgents.queryAPI(
            string(abi.encodePacked(
                "https://api.lending-protocol.xyz/v1/health/",
                _toHexString(protocol),
                "/",
                _toHexString(user)
            )),
            "$.health_factor"
        );
        if (raw.length == 0) revert HealthFactorFailed();

        uint256 healthFactor = abi.decode(raw, (uint256));
        return healthFactor < minHF;
    }

    /// @notice Convenience wrapper used by ExecutionVerifier for the collateral-guard task type.
    function evaluateHealthFactor(address lendingProtocol, address user)
        external
        returns (bool triggered, uint256 healthFactor)
    {
        bytes memory raw = somniaAgents.queryAPI(
            string(abi.encodePacked(
                "https://api.lending-protocol.xyz/v1/health/",
                _toHexString(lendingProtocol),
                "/",
                _toHexString(user)
            )),
            "$.health_factor"
        );
        if (raw.length == 0) revert HealthFactorFailed();
        healthFactor = abi.decode(raw, (uint256));
        triggered = healthFactor < 1.3e18; // default threshold; callers should use evaluate() for custom values
    }

    // ─── APY spread trigger ───────────────────────────────────────────────────

    /// Params: (string poolA_id, string poolB_id, uint256 minSpreadBPS)
    function _evaluateAPYSpread(TriggerCondition memory cond) internal returns (bool) {
        (string memory poolA, string memory poolB, uint256 minSpreadBPS) =
            abi.decode(cond.params, (string, string, uint256));

        bytes memory rawA = somniaAgents.queryAPI(
            string(abi.encodePacked("https://api.defi-yields.xyz/v1/pool/", poolA)),
            "$.apy_bps"
        );
        bytes memory rawB = somniaAgents.queryAPI(
            string(abi.encodePacked("https://api.defi-yields.xyz/v1/pool/", poolB)),
            "$.apy_bps"
        );
        if (rawA.length == 0 || rawB.length == 0) revert APYFetchFailed();

        uint256 apyA = abi.decode(rawA, (uint256));
        uint256 apyB = abi.decode(rawB, (uint256));
        uint256 spread = apyA > apyB ? apyA - apyB : apyB - apyA;
        return spread >= minSpreadBPS;
    }

    // ─── Block interval trigger ───────────────────────────────────────────────

    /// Params: (uint256 anchorBlock, uint256 intervalBlocks)
    /// Pure — no API call needed; uses block.number directly.
    function _evaluateBlockInterval(TriggerCondition memory cond) internal view returns (bool) {
        (uint256 anchorBlock, uint256 intervalBlocks) = abi.decode(cond.params, (uint256, uint256));
        if (intervalBlocks == 0) revert InvalidParams();
        return (block.number - anchorBlock) % intervalBlocks == 0 && block.number > anchorBlock;
    }

    // ─── Encoding helpers (for off-chain SDK / tests) ─────────────────────────

    function encodePriceTrigger(address token, uint256 thresholdUSD, bool triggerBelow)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: triggerBelow ? TriggerType.PriceBelow : TriggerType.PriceAbove,
            params: abi.encode(token, thresholdUSD)
        }));
    }

    function encodeHealthFactorTrigger(address protocol, address user, uint256 minHF)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.HealthFactor,
            params: abi.encode(protocol, user, minHF)
        }));
    }

    function encodeAPYSpreadTrigger(string calldata poolA, string calldata poolB, uint256 minSpreadBPS)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.APYSpread,
            params: abi.encode(poolA, poolB, minSpreadBPS)
        }));
    }

    function encodeBlockIntervalTrigger(uint256 anchorBlock, uint256 intervalBlocks)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.BlockInterval,
            params: abi.encode(anchorBlock, intervalBlocks)
        }));
    }

    // ─── Internal utils ───────────────────────────────────────────────────────

    function _toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        bytes memory hex_chars = "0123456789abcdef";
        uint160 value = uint160(addr);
        for (uint256 i = 41; i >= 2; i--) {
            buffer[i] = hex_chars[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}
