// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Somnia's native on-chain AI compute interface (async task pattern).
/// Contracts call createTask(); Somnia's executor fetches data off-chain, then
/// calls back via onAgentResponse() in a separate transaction.
interface ISomniaAgents {
    function createTask(uint256 agentId, bytes calldata taskData)
        external payable returns (uint256 taskId);
}

/// @notice Trigger-condition evaluator backed by Somnia Agents' async oracle.
///
/// Flow:
///   1. Call requestOracleUpdate(trigger) — queues a Somnia compute task.
///   2. Somnia's executor fetches data and calls onAgentResponse(taskId, result).
///   3. evaluate(trigger) reads the cached result (reverts with OracleResultStale if expired).
///
/// BlockInterval triggers are pure (block.number only) — no oracle call needed.
/// When somniaAgents == address(0), API triggers are cached as triggered=true (optimistic).
contract SomniaAgentsAdapter {
    // ─── Types ───────────────────────────────────────────────────────────────

    enum TriggerType {
        PriceBelow,
        PriceAbove,
        HealthFactor,
        APYSpread,
        BlockInterval
    }

    struct TriggerCondition {
        TriggerType triggerType;
        bytes       params;
    }

    struct CachedResult {
        bool    triggered;
        uint256 cachedAt;  // block.number when result was stored
    }

    // ─── Constants ───────────────────────────────────────────────────────────

    // 150 blocks ≈ 60 seconds at Somnia's 400ms block time — matches the default claim window.
    uint256 public constant CACHE_VALID_BLOCKS = 150;

    // ─── Storage ─────────────────────────────────────────────────────────────

    ISomniaAgents public immutable somniaAgents;
    string        public priceFeedBase;
    address       public immutable owner;
    uint256       public oracleAgentId;

    mapping(bytes32 => CachedResult) internal _cache;  // keccak256(trigger) => result

    // ─── Errors ──────────────────────────────────────────────────────────────

    error OracleResultStale();
    error NotSomniaAgents();
    error Unauthorized();
    error UnsupportedTriggerType();
    error InvalidParams();

    // ─── Events ──────────────────────────────────────────────────────────────

    event OracleUpdateRequested(bytes32 indexed triggerHash, uint256 somniaTaskId);
    event OracleResultCached(bytes32 indexed triggerHash, bool triggered);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _somniaAgents, string memory _priceFeedBase) {
        owner        = msg.sender;
        somniaAgents = ISomniaAgents(_somniaAgents);
        priceFeedBase = _priceFeedBase;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setOracleAgentId(uint256 id) external {
        if (msg.sender != owner) revert Unauthorized();
        oracleAgentId = id;
    }

    // ─── Request oracle update ────────────────────────────────────────────────

    /// @notice Queue an oracle update for the given encoded TriggerCondition.
    ///         BlockInterval: resolved inline (pure), result cached immediately.
    ///         API triggers: calls Somnia Agents, result cached on callback.
    ///         somniaAgents == address(0): cached as triggered=true (optimistic).
    /// @return somniaTaskId  Somnia task ID; 0 for pure/optimistic paths.
    function requestOracleUpdate(bytes calldata trigger) external returns (uint256 somniaTaskId) {
        TriggerCondition memory cond = abi.decode(trigger, (TriggerCondition));
        bytes32 h = keccak256(trigger);

        if (cond.triggerType == TriggerType.BlockInterval) {
            (, uint256 interval) = abi.decode(cond.params, (uint256, uint256));
            if (interval == 0) revert InvalidParams();
            bool result = _evaluateBlockInterval(cond);
            _cache[h] = CachedResult(result, block.number);
            emit OracleResultCached(h, result);
            return 0;
        }

        // Validate params before sending to oracle
        if (cond.triggerType == TriggerType.PriceBelow || cond.triggerType == TriggerType.PriceAbove) {
            (address token,) = abi.decode(cond.params, (address, uint256));
            if (token == address(0)) revert InvalidParams();
        } else if (cond.triggerType == TriggerType.HealthFactor) {
            (address protocol, address user,) = abi.decode(cond.params, (address, address, uint256));
            if (protocol == address(0) || user == address(0)) revert InvalidParams();
        }

        if (address(somniaAgents) == address(0)) {
            _cache[h] = CachedResult(true, block.number);
            emit OracleResultCached(h, true);
            return 0;
        }

        // taskData encodes both the trigger and priceFeedBase so Somnia passes it back in the callback.
        bytes memory taskData = abi.encode(trigger, priceFeedBase);
        somniaTaskId = somniaAgents.createTask(oracleAgentId, taskData);
        emit OracleUpdateRequested(h, somniaTaskId);
    }

    // ─── Somnia callback ──────────────────────────────────────────────────────

    /// @notice Called by Somnia's executor once the compute task completes.
    ///         Only callable by address(somniaAgents).
    /// @param originalTaskData  The taskData bytes originally passed to createTask —
    ///                          Somnia echoes these back so we can recover the trigger without storage.
    function onAgentResponse(uint256, bytes calldata originalTaskData, bytes calldata result) external {
        if (msg.sender != address(somniaAgents)) revert NotSomniaAgents();

        (bytes memory trigger,) = abi.decode(originalTaskData, (bytes, string));
        TriggerCondition memory cond = abi.decode(trigger, (TriggerCondition));
        bool triggered = _evaluateFromResult(cond, result);
        bytes32 h = keccak256(trigger);
        _cache[h] = CachedResult(triggered, block.number);
        emit OracleResultCached(h, triggered);
    }

    // ─── Evaluate (reads cache) ───────────────────────────────────────────────

    /// @notice Returns whether a trigger condition is currently satisfied.
    ///         BlockInterval: evaluated inline (always fresh).
    ///         Others: reads cache; reverts with OracleResultStale if expired or absent.
    function evaluate(bytes calldata trigger) external view returns (bool) {
        TriggerCondition memory cond = abi.decode(trigger, (TriggerCondition));

        if (cond.triggerType == TriggerType.BlockInterval) {
            return _evaluateBlockInterval(cond);
        }

        CachedResult memory cached = _cache[keccak256(trigger)];
        if (cached.cachedAt == 0 || block.number - cached.cachedAt > CACHE_VALID_BLOCKS) {
            revert OracleResultStale();
        }
        return cached.triggered;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    function _evaluateBlockInterval(TriggerCondition memory cond) internal view returns (bool) {
        (uint256 anchorBlock, uint256 intervalBlocks) = abi.decode(cond.params, (uint256, uint256));
        if (intervalBlocks == 0) revert InvalidParams();
        return (block.number - anchorBlock) % intervalBlocks == 0 && block.number > anchorBlock;
    }

    /// @dev Parses the raw bytes returned by Somnia's executor and evaluates the condition.
    ///      Empty result is treated as not-triggered (oracle fetch failed).
    function _evaluateFromResult(TriggerCondition memory cond, bytes memory result)
        internal pure returns (bool)
    {
        if (result.length == 0) return false;

        if (cond.triggerType == TriggerType.PriceBelow || cond.triggerType == TriggerType.PriceAbove) {
            (, uint256 threshold) = abi.decode(cond.params, (address, uint256));
            uint256 price = abi.decode(result, (uint256));
            return cond.triggerType == TriggerType.PriceBelow
                ? price < threshold
                : price > threshold;
        }
        if (cond.triggerType == TriggerType.HealthFactor) {
            (,, uint256 minHF) = abi.decode(cond.params, (address, address, uint256));
            uint256 hf = abi.decode(result, (uint256));
            return hf < minHF;
        }
        if (cond.triggerType == TriggerType.APYSpread) {
            (,, uint256 minSpreadBPS) = abi.decode(cond.params, (string, string, uint256));
            (uint256 apyA, uint256 apyB) = abi.decode(result, (uint256, uint256));
            uint256 spread = apyA > apyB ? apyA - apyB : apyB - apyA;
            return spread >= minSpreadBPS;
        }
        return false;
    }

    // ─── Encoding helpers (pure) ──────────────────────────────────────────────

    function encodePriceTrigger(address token, uint256 thresholdUSD, bool triggerBelow)
        external pure returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: triggerBelow ? TriggerType.PriceBelow : TriggerType.PriceAbove,
            params: abi.encode(token, thresholdUSD)
        }));
    }

    function encodeHealthFactorTrigger(address protocol, address user, uint256 minHF)
        external pure returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.HealthFactor,
            params: abi.encode(protocol, user, minHF)
        }));
    }

    function encodeAPYSpreadTrigger(string calldata poolA, string calldata poolB, uint256 minSpreadBPS)
        external pure returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.APYSpread,
            params: abi.encode(poolA, poolB, minSpreadBPS)
        }));
    }

    function encodeBlockIntervalTrigger(uint256 anchorBlock, uint256 intervalBlocks)
        external pure returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.BlockInterval,
            params: abi.encode(anchorBlock, intervalBlocks)
        }));
    }
}
