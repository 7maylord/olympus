// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ── Official Somnia Agents Platform ──────────────────────────────────────────
// Testnet:  0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776  (chain ID 50312)
// Mainnet:  0x5E5205CF39E766118C01636bED000A54D93163E6  (chain ID 5031)
interface ISomniaAgentsPlatform {
    enum ResponseStatus { None, Pending, Success, Failed, TimedOut }
    enum ConsensusType  { Majority, Threshold }

    struct Response {
        address        validator;
        bytes          result;
        ResponseStatus status;
        uint256        receipt;
        uint256        timestamp;
        uint256        executionCost;
    }

    struct Request {
        uint256 agentId;
        address callbackAddress;
        bytes4  callbackSelector;
        bytes   payload;
    }

    /// @dev Send getRequestDeposit() + (pricePerAgent × validators) as msg.value.
    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4  callbackSelector,
        bytes   calldata payload
    ) external payable returns (uint256 requestId);

    /// @dev Base deposit required in addition to per-agent costs.
    function getRequestDeposit() external view returns (uint256);
}

/// @title  SomniaAgentsAdapter
/// @notice Bridges Olympus trigger conditions to the Somnia Agents oracle platform.
///         For price / health / APY triggers, calls the built-in JSON API agent
///         (ID 13174292974160097713) to fetch off-chain data.  Results are cached
///         for CACHE_VALID_BLOCKS and consumed by ExecutionVerifier.evaluate().
///
///         Trigger condition ABI encoding by type:
///           PriceBelow / PriceAbove  → abi.encode(string tokenId, uint256 thresholdUSD18)
///             tokenId: CoinGecko asset ID, e.g. "ethereum", "bitcoin"
///             thresholdUSD18: price threshold scaled by 1e18
///           HealthFactor             → abi.encode(string protocol, address user, uint256 minHF18)
///           APYSpread                → abi.encode(string poolA, string poolB, uint256 minSpreadBPS)
///           BlockInterval            → abi.encode(uint256 anchorBlock, uint256 intervalBlocks)
///
///         JSON API agent payload: abi.encode(string url, string jsonPath)
///           The agent fetches `url` and returns the numeric value at `jsonPath`
///           as an ABI-encoded uint256 (scaled by 1e18).
contract SomniaAgentsAdapter {

    // ── Constants ─────────────────────────────────────────────────────────────
    /// @dev Somnia built-in JSON API agent ID (same on testnet and mainnet).
    uint256 public constant JSON_API_AGENT_ID  = 13174292974160097713;
    /// @dev Default subcommittee size (3 validators reach majority consensus).
    uint256 public constant DEFAULT_VALIDATORS = 3;
    /// @dev Cost per validator on testnet (0.03 STT).
    uint256 public constant COST_PER_VALIDATOR = 0.03 ether;
    /// @dev Cache validity window.  150 blocks ≈ 5 min at Somnia's ~2 s block time.
    uint256 public constant CACHE_VALID_BLOCKS = 150;

    // ── Trigger types ─────────────────────────────────────────────────────────
    enum TriggerType {
        PriceBelow,   // 0
        PriceAbove,   // 1
        HealthFactor, // 2
        APYSpread,    // 3
        BlockInterval // 4
    }

    struct TriggerCondition {
        TriggerType triggerType;
        bytes       params;
    }

    struct CachedResult {
        bool    triggered;
        uint256 cachedAt; // block.number when result was stored
    }

    // ── State ─────────────────────────────────────────────────────────────────
    ISomniaAgentsPlatform public immutable platform;
    address               public immutable owner;

    /// @dev requestId → keccak256(trigger bytes) for cache lookup in handleResponse
    mapping(uint256 => bytes32) public  pendingRequests;
    /// @dev requestId → original trigger bytes to re-evaluate result against params
    mapping(uint256 => bytes)   internal _pendingTriggers;
    /// @dev keccak256(trigger) → cached evaluation result
    mapping(bytes32 => CachedResult) internal _cache;

    // ── Errors / Events ───────────────────────────────────────────────────────
    error OracleResultStale();
    error NotSomniaAgentsPlatform();
    error Unauthorized();
    error InvalidParams();
    error InsufficientPayment(uint256 required, uint256 sent);

    event OracleUpdateRequested(bytes32 indexed triggerHash, uint256 requestId);
    event OracleResultCached(bytes32 indexed triggerHash, bool triggered);

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _platform  Somnia Agents platform contract address.
    ///                   Pass address(0) for local dev — oracle calls short-circuit to true.
    constructor(address _platform) {
        owner    = msg.sender;
        platform = ISomniaAgentsPlatform(_platform);
    }

    /// @dev Receive gas rebates from the platform.
    receive() external payable {}

    // ── Oracle request ────────────────────────────────────────────────────────

    /// @notice Request an oracle evaluation for a trigger condition.
    ///         BlockInterval triggers are evaluated on-chain for free.
    ///         All other types require STT payment: call requiredPayment() first.
    /// @param  trigger  ABI-encoded TriggerCondition (use encode*Trigger helpers).
    /// @return requestId  Somnia platform request ID (0 for BlockInterval / dev mode).
    function requestOracleUpdate(bytes calldata trigger)
        external payable returns (uint256 requestId)
    {
        TriggerCondition memory cond = abi.decode(trigger, (TriggerCondition));
        bytes32 h = keccak256(trigger);

        // BlockInterval: evaluate purely on-chain, no oracle needed
        if (cond.triggerType == TriggerType.BlockInterval) {
            bool result = _evaluateBlockInterval(cond);
            _cache[h] = CachedResult(result, block.number);
            emit OracleResultCached(h, result);
            return 0;
        }

        _validateParams(cond);

        // Dev / fallback mode: platform not set → cache true immediately
        if (address(platform) == address(0)) {
            _cache[h] = CachedResult(true, block.number);
            emit OracleResultCached(h, true);
            return 0;
        }

        // Verify payment covers deposit + per-agent cost
        uint256 deposit  = platform.getRequestDeposit();
        uint256 required = deposit + COST_PER_VALIDATOR * DEFAULT_VALIDATORS;
        if (msg.value < required) revert InsufficientPayment(required, msg.value);

        // Build JSON API payload and submit request
        bytes memory payload = _buildPayload(cond);

        requestId = platform.createRequest{value: required}(
            JSON_API_AGENT_ID,
            address(this),
            this.handleResponse.selector,
            payload
        );

        pendingRequests[requestId]  = h;
        _pendingTriggers[requestId] = trigger;
        emit OracleUpdateRequested(h, requestId);

        // Refund any overpayment
        uint256 excess = msg.value - required;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "Refund failed");
        }
    }

    // ── Somnia platform callback ──────────────────────────────────────────────

    /// @notice Called by the Somnia Agents platform when validator consensus is reached.
    ///         Decodes the numeric result from the JSON API agent and evaluates the trigger.
    function handleResponse(
        uint256 requestId,
        ISomniaAgentsPlatform.Response[] memory responses,
        ISomniaAgentsPlatform.ResponseStatus,
        ISomniaAgentsPlatform.Request memory
    ) external {
        if (msg.sender != address(platform)) revert NotSomniaAgentsPlatform();

        bytes32 h            = pendingRequests[requestId];
        bytes memory trigger = _pendingTriggers[requestId];
        if (h == bytes32(0)) return; // unknown requestId

        delete pendingRequests[requestId];
        delete _pendingTriggers[requestId];

        // Find first successful validator response with a valid result
        bytes memory result;
        for (uint256 i = 0; i < responses.length; i++) {
            if (responses[i].status == ISomniaAgentsPlatform.ResponseStatus.Success
                && responses[i].result.length >= 32)
            {
                result = responses[i].result;
                break;
            }
        }

        // No valid response → leave cache stale; caller can retry requestOracleUpdate
        if (result.length < 32) return;

        // JSON API agent returns ABI-encoded uint256 (value scaled by 1e18)
        uint256 value = abi.decode(result, (uint256));
        TriggerCondition memory cond = abi.decode(trigger, (TriggerCondition));
        bool triggered = _evaluateFromResult(cond, value);

        _cache[h] = CachedResult(triggered, block.number);
        emit OracleResultCached(h, triggered);
    }

    // ── Evaluate (called by ExecutionVerifier.verifyAndSettle) ───────────────

    /// @notice Returns whether a trigger condition is currently met.
    ///         BlockInterval is checked on-chain.  All others require a fresh cache entry
    ///         populated by a recent requestOracleUpdate → handleResponse cycle.
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

    // ── Convenience view ──────────────────────────────────────────────────────

    /// @notice STT (in wei) to send with requestOracleUpdate for non-block triggers.
    function requiredPayment() external view returns (uint256) {
        if (address(platform) == address(0)) return 0;
        return platform.getRequestDeposit() + COST_PER_VALIDATOR * DEFAULT_VALIDATORS;
    }

    // ── Encode helpers ────────────────────────────────────────────────────────

    /// @param tokenId       CoinGecko asset ID, e.g. "ethereum", "bitcoin", "usd-coin"
    /// @param thresholdUSD18 Price threshold scaled by 1e18 (e.g. 2000e18 = $2000)
    function encodePriceTrigger(string calldata tokenId, uint256 thresholdUSD18, bool triggerBelow)
        external pure returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: triggerBelow ? TriggerType.PriceBelow : TriggerType.PriceAbove,
            params: abi.encode(tokenId, thresholdUSD18)
        }));
    }

    /// @param protocol  Protocol name, e.g. "aave-v3"
    /// @param user      Borrower address to monitor
    /// @param minHF18   Minimum health factor scaled by 1e18 (e.g. 1.2e18 = 1.2)
    function encodeHealthFactorTrigger(string calldata protocol, address user, uint256 minHF18)
        external pure returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.HealthFactor,
            params: abi.encode(protocol, user, minHF18)
        }));
    }

    /// @param poolA        DefiLlama pool UUID for source
    /// @param poolB        DefiLlama pool UUID for target
    /// @param minSpreadBPS Minimum APY spread in basis points (e.g. 200 = 2%)
    function encodeAPYSpreadTrigger(string calldata poolA, string calldata poolB, uint256 minSpreadBPS)
        external pure returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.APYSpread,
            params: abi.encode(poolA, poolB, minSpreadBPS)
        }));
    }

    /// @param anchorBlock    Block number the interval is measured from
    /// @param intervalBlocks Execute every N blocks after anchorBlock
    function encodeBlockIntervalTrigger(uint256 anchorBlock, uint256 intervalBlocks)
        external pure returns (bytes memory)
    {
        return abi.encode(TriggerCondition({
            triggerType: TriggerType.BlockInterval,
            params: abi.encode(anchorBlock, intervalBlocks)
        }));
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    /// @dev Build the JSON API agent payload: ABI-encoded (url, jsonPath).
    ///      The Somnia JSON API agent fetches `url` and extracts the numeric value
    ///      at `jsonPath`, returning it as ABI-encoded uint256 scaled by 1e18.
    function _buildPayload(TriggerCondition memory cond) internal pure returns (bytes memory) {
        if (cond.triggerType == TriggerType.PriceBelow || cond.triggerType == TriggerType.PriceAbove) {
            (string memory tokenId,) = abi.decode(cond.params, (string, uint256));
            // CoinGecko free API — no key required
            string memory url = string(abi.encodePacked(
                "https://api.coingecko.com/api/v3/simple/price?ids=",
                tokenId,
                "&vs_currencies=usd"
            ));
            string memory jsonPath = string(abi.encodePacked("$.", tokenId, ".usd"));
            return abi.encode(url, jsonPath);
        }
        if (cond.triggerType == TriggerType.HealthFactor) {
            (, address user,) = abi.decode(cond.params, (string, address, uint256));
            // Aave v3 user account data endpoint
            string memory url = string(abi.encodePacked(
                "https://api.aave.com/data/users/",
                _addressToHex(user)
            ));
            return abi.encode(url, "$.healthFactor");
        }
        if (cond.triggerType == TriggerType.APYSpread) {
            (string memory poolA,,) = abi.decode(cond.params, (string, string, uint256));
            // DefiLlama yields API — poolA UUID
            string memory url = string(abi.encodePacked(
                "https://yields.llama.fi/pool/",
                poolA
            ));
            return abi.encode(url, "$.data.apy");
        }
        return "";
    }

    function _validateParams(TriggerCondition memory cond) internal pure {
        if (cond.triggerType == TriggerType.PriceBelow || cond.triggerType == TriggerType.PriceAbove) {
            (string memory tokenId,) = abi.decode(cond.params, (string, uint256));
            if (bytes(tokenId).length == 0) revert InvalidParams();
        } else if (cond.triggerType == TriggerType.HealthFactor) {
            (, address user,) = abi.decode(cond.params, (string, address, uint256));
            if (user == address(0)) revert InvalidParams();
        }
    }

    function _evaluateBlockInterval(TriggerCondition memory cond) internal view returns (bool) {
        (uint256 anchorBlock, uint256 intervalBlocks) = abi.decode(cond.params, (uint256, uint256));
        if (intervalBlocks == 0) revert InvalidParams();
        return block.number > anchorBlock && (block.number - anchorBlock) % intervalBlocks == 0;
    }

    /// @dev value is the ABI-decoded uint256 returned by the JSON API agent (scaled 1e18).
    function _evaluateFromResult(TriggerCondition memory cond, uint256 value) internal pure returns (bool) {
        if (cond.triggerType == TriggerType.PriceBelow) {
            (, uint256 threshold) = abi.decode(cond.params, (string, uint256));
            return value < threshold;
        }
        if (cond.triggerType == TriggerType.PriceAbove) {
            (, uint256 threshold) = abi.decode(cond.params, (string, uint256));
            return value > threshold;
        }
        if (cond.triggerType == TriggerType.HealthFactor) {
            (,, uint256 minHF) = abi.decode(cond.params, (string, address, uint256));
            return value < minHF;
        }
        if (cond.triggerType == TriggerType.APYSpread) {
            (,, uint256 minSpreadBPS) = abi.decode(cond.params, (string, string, uint256));
            // Agent encodes apyA in upper 128 bits, apyB in lower 128 bits
            uint256 apyA   = value >> 128;
            uint256 apyB   = value & type(uint128).max;
            uint256 spread = apyA > apyB ? apyA - apyB : apyB - apyA;
            return spread >= minSpreadBPS;
        }
        return false;
    }

    function _addressToHex(address addr) internal pure returns (string memory) {
        bytes memory buf = new bytes(42);
        buf[0] = '0';
        buf[1] = 'x';
        bytes memory b = abi.encodePacked(addr);
        for (uint256 i = 0; i < 20; i++) {
            uint8 v = uint8(b[i]);
            buf[2 + i * 2]     = _hexNibble(v >> 4);
            buf[2 + i * 2 + 1] = _hexNibble(v & 0x0f);
        }
        return string(buf);
    }

    function _hexNibble(uint8 n) internal pure returns (bytes1) {
        return n < 10 ? bytes1(0x30 + n) : bytes1(0x61 + n - 10);
    }
}
