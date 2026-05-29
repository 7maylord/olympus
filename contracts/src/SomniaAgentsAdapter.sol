// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMantleAgents {
    function createTask(uint256 agentId, bytes calldata taskData)
        external payable returns (uint256 taskId);
}

contract MantleAgentsAdapter {

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
        uint256 cachedAt;
    }

    uint256 public constant CACHE_VALID_BLOCKS = 150;

    IMantleAgents public immutable mantleAgents;
    string        public priceFeedBase;
    address       public immutable owner;
    uint256       public oracleAgentId;

    mapping(bytes32 => CachedResult) internal _cache;

    error OracleResultStale();
    error NotMantleAgents();
    error Unauthorized();
    error UnsupportedTriggerType();
    error InvalidParams();

    event OracleUpdateRequested(bytes32 indexed triggerHash, uint256 mantleTaskId);
    event OracleResultCached(bytes32 indexed triggerHash, bool triggered);

    constructor(address _mantleAgents, string memory _priceFeedBase) {
        owner        = msg.sender;
        mantleAgents = IMantleAgents(_mantleAgents);
        priceFeedBase = _priceFeedBase;
    }

    function setOracleAgentId(uint256 id) external {
        if (msg.sender != owner) revert Unauthorized();
        oracleAgentId = id;
    }

    function requestOracleUpdate(bytes calldata trigger) external returns (uint256 mantleTaskId) {
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

        if (cond.triggerType == TriggerType.PriceBelow || cond.triggerType == TriggerType.PriceAbove) {
            (address token,) = abi.decode(cond.params, (address, uint256));
            if (token == address(0)) revert InvalidParams();
        } else if (cond.triggerType == TriggerType.HealthFactor) {
            (address protocol, address user,) = abi.decode(cond.params, (address, address, uint256));
            if (protocol == address(0) || user == address(0)) revert InvalidParams();
        }

        if (address(mantleAgents) == address(0)) {
            _cache[h] = CachedResult(true, block.number);
            emit OracleResultCached(h, true);
            return 0;
        }

        bytes memory taskData = abi.encode(trigger, priceFeedBase);
        mantleTaskId = mantleAgents.createTask(oracleAgentId, taskData);
        emit OracleUpdateRequested(h, mantleTaskId);
    }

    function onAgentResponse(uint256, bytes calldata originalTaskData, bytes calldata result) external {
        if (msg.sender != address(mantleAgents)) revert NotMantleAgents();

        (bytes memory trigger,) = abi.decode(originalTaskData, (bytes, string));
        TriggerCondition memory cond = abi.decode(trigger, (TriggerCondition));
        bool triggered = _evaluateFromResult(cond, result);
        bytes32 h = keccak256(trigger);
        _cache[h] = CachedResult(triggered, block.number);
        emit OracleResultCached(h, triggered);
    }

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

    function _evaluateBlockInterval(TriggerCondition memory cond) internal view returns (bool) {
        (uint256 anchorBlock, uint256 intervalBlocks) = abi.decode(cond.params, (uint256, uint256));
        if (intervalBlocks == 0) revert InvalidParams();
        return (block.number - anchorBlock) % intervalBlocks == 0 && block.number > anchorBlock;
    }

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
