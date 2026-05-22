// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/BountyEscrow.sol";
import "../src/TaskRegistry.sol";
import "../src/SomniaAgentsAdapter.sol";
import "../src/ExecutionVerifier.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);

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

        AgentRegistry agentRegistry = new AgentRegistry(treasury);
        console2.log("AgentRegistry        :", address(agentRegistry));

        BountyEscrow bountyEscrow = new BountyEscrow(treasury);
        console2.log("BountyEscrow         :", address(bountyEscrow));

        SomniaAgentsAdapter somniaAdapter = new SomniaAgentsAdapter(somniaAgents, priceBase);
        console2.log("SomniaAgentsAdapter  :", address(somniaAdapter));

        TaskRegistry taskRegistry = new TaskRegistry(
            address(agentRegistry),
            address(bountyEscrow),
            treasury
        );
        console2.log("TaskRegistry         :", address(taskRegistry));

        ExecutionVerifier executionVerifier = new ExecutionVerifier(
            address(taskRegistry),
            address(agentRegistry),
            address(somniaAdapter)
        );
        console2.log("ExecutionVerifier    :", address(executionVerifier));

        agentRegistry.setVerifier(address(taskRegistry));

        bountyEscrow.setTaskRegistry(address(taskRegistry));

        taskRegistry.setExecutionVerifier(address(executionVerifier));

        vm.stopBroadcast();

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
