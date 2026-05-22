// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/BountyEscrow.sol";
import "../src/TaskRegistry.sol";
import "../src/SomniaAgentsAdapter.sol";
import "../src/ExecutionVerifier.sol";

/// @notice Deploys all Olympus contracts in dependency order and wires them together.
///
/// Required env vars:
///   SOMNIA_RPC_URL          — Somnia testnet RPC
///   DEPLOYER_PRIVATE_KEY    — deployer key (never commit)
///   TREASURY_ADDRESS        — address that receives listing fees + forfeited bonds
///   SOMNIA_AGENTS_ADDRESS   — address of Somnia's native ISomniaAgents precompile
///   PRICE_FEED_BASE_URL     — base URL for price oracle API (e.g. https://api.price-feed.xyz/v1/)
///
/// Usage:
///   forge script script/Deploy.s.sol \
///     --rpc-url $SOMNIA_RPC_URL \
///     --broadcast \
///     --verify
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        // Treasury defaults to deployer on testnet; override with TREASURY_ADDRESS in prod
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);

        // Somnia's native on-chain compute precompile — stub address for testnet until confirmed
        address somniaAgents = vm.envOr("SOMNIA_AGENTS_ADDRESS", address(0));

        string memory priceBase = vm.envOr(
            "PRICE_FEED_BASE_URL",
            string("https://api.price-feed.xyz/v1/")
        );

        console2.log("=== Olympus Protocol Deployment ===");
        console2.log("Deployer  :", deployer);
        console2.log("Treasury  :", treasury);
        console2.log("Chain ID  :", block.chainid);
        console2.log("");

        vm.startBroadcast(deployerKey);

        // ── 1. AgentRegistry ─────────────────────────────────────────────────
        AgentRegistry agentRegistry = new AgentRegistry(treasury);
        console2.log("AgentRegistry        :", address(agentRegistry));

        // ── 2. BountyEscrow ──────────────────────────────────────────────────
        BountyEscrow bountyEscrow = new BountyEscrow(treasury);
        console2.log("BountyEscrow         :", address(bountyEscrow));

        // ── 3. SomniaAgentsAdapter ────────────────────────────────────────────
        SomniaAgentsAdapter somniaAdapter = new SomniaAgentsAdapter(somniaAgents, priceBase);
        console2.log("SomniaAgentsAdapter  :", address(somniaAdapter));

        // ── 4. TaskRegistry ───────────────────────────────────────────────────
        TaskRegistry taskRegistry = new TaskRegistry(
            address(agentRegistry),
            address(bountyEscrow),
            treasury
        );
        console2.log("TaskRegistry         :", address(taskRegistry));

        // ── 5. ExecutionVerifier ──────────────────────────────────────────────
        ExecutionVerifier executionVerifier = new ExecutionVerifier(
            address(taskRegistry),
            address(agentRegistry),
            address(somniaAdapter)
        );
        console2.log("ExecutionVerifier    :", address(executionVerifier));

        // ── 6. Wire contracts ─────────────────────────────────────────────────
        // AgentRegistry: only TaskRegistry can call postFeedback
        agentRegistry.setVerifier(address(taskRegistry));

        // BountyEscrow: only TaskRegistry can move funds
        bountyEscrow.setTaskRegistry(address(taskRegistry));

        // TaskRegistry: delegate proof verification to ExecutionVerifier
        taskRegistry.setExecutionVerifier(address(executionVerifier));

        vm.stopBroadcast();

        // ── 7. Verify wiring ──────────────────────────────────────────────────
        require(agentRegistry.verifier()           == address(taskRegistry),       "AgentRegistry wiring");
        require(bountyEscrow.taskRegistry()        == address(taskRegistry),       "BountyEscrow wiring");
        require(taskRegistry.executionVerifier()   == address(executionVerifier),  "TaskRegistry wiring");
        require(taskRegistry.agentRegistry()       == agentRegistry,               "agentRegistry ref");
        require(taskRegistry.bountyEscrow()        == bountyEscrow,                "bountyEscrow ref");
        require(executionVerifier.taskRegistry()   == taskRegistry,                "verifier-taskReg");
        require(executionVerifier.agentRegistry()  == agentRegistry,               "verifier-agentReg");

        console2.log("");
        console2.log("All wiring verified.");
        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("");
        console2.log("Copy these into your .env:");
        console2.log("TASK_REGISTRY_ADDRESS=",      address(taskRegistry));
        console2.log("AGENT_REGISTRY_ADDRESS=",     address(agentRegistry));
        console2.log("BOUNTY_ESCROW_ADDRESS=",      address(bountyEscrow));
        console2.log("EXECUTION_VERIFIER_ADDRESS=", address(executionVerifier));
        console2.log("SOMNIA_AGENTS_ADAPTER_ADDRESS=", address(somniaAdapter));
    }
}
