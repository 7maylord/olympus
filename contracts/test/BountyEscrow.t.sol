// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BountyEscrow.sol";

/// Minimal attacker that tries to re-enter on receive
contract ReentrantAttacker {
    BountyEscrow escrow;
    uint256 taskId;
    bool armed;

    constructor(address _escrow) { escrow = BountyEscrow(_escrow); }

    function arm(uint256 _taskId) external { taskId = _taskId; armed = true; }

    receive() external payable {
        if (armed) {
            armed = false;
            // attempt re-entry on settleSuccess — should revert
            try escrow.settleSuccess(taskId, address(this)) {} catch {}
        }
    }
}

contract BountyEscrowTest is Test {
    BountyEscrow escrow;
    address registry  = makeAddr("registry");
    address treasury  = makeAddr("treasury");
    address poster    = makeAddr("poster");
    address agent     = makeAddr("agent");

    uint256 constant BOUNTY     = 1 ether;
    uint256 constant CLAIM_BOND = 0.0001 ether;

    // Redeclare events for vm.expectEmit
    event BountyDeposited(uint256 indexed taskId, uint256 amount);
    event ClaimBondDeposited(uint256 indexed taskId, address indexed agent, uint256 amount);
    event BountyReleased(uint256 indexed taskId, address indexed recipient, uint256 amount);
    event BountyRefunded(uint256 indexed taskId, address indexed poster, uint256 amount);
    event ClaimBondForfeited(uint256 indexed taskId, address indexed agent, uint256 amount);
    event ClaimBondReturned(uint256 indexed taskId, address indexed agent, uint256 amount);

    function setUp() public {
        escrow = new BountyEscrow(treasury);
        escrow.setTaskRegistry(registry);
        vm.deal(registry, 100 ether);
        vm.deal(agent,    10 ether);
    }

    // ─── Access control ──────────────────────────────────────────────────────

    function test_non_registry_cannot_deposit() public {
        vm.deal(poster, BOUNTY);
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.NotTaskRegistry.selector);
        escrow.depositBounty{value: BOUNTY}(1);
    }

    function test_non_registry_cannot_settle() public {
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.NotTaskRegistry.selector);
        escrow.settleSuccess(1, agent);
    }

    function test_non_registry_cannot_forfeit() public {
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.NotTaskRegistry.selector);
        escrow.forfeitBond(1);
    }

    function test_non_registry_cannot_refund() public {
        vm.prank(poster);
        vm.expectRevert(BountyEscrow.NotTaskRegistry.selector);
        escrow.refundBounty(1, poster);
    }

    function test_set_registry_only_once() public {
        BountyEscrow fresh = new BountyEscrow(treasury);
        fresh.setTaskRegistry(registry);
        vm.expectRevert("Already set");
        fresh.setTaskRegistry(agent);
    }

    // ─── Deposit ─────────────────────────────────────────────────────────────

    function test_deposit_bounty_stores_amount() public {
        vm.prank(registry);
        escrow.depositBounty{value: BOUNTY}(1);

        (uint256 bounty,,) = escrow.getEntry(1);
        assertEq(bounty, BOUNTY);
    }

    function test_deposit_bounty_emits_event() public {
        vm.expectEmit(true, false, false, true);
        emit BountyDeposited(1, BOUNTY);

        vm.prank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
    }

    function test_deposit_bounty_reverts_duplicate() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        vm.expectRevert(BountyEscrow.AlreadyDeposited.selector);
        escrow.depositBounty{value: BOUNTY}(1);
        vm.stopPrank();
    }

    function test_deposit_claim_bond_stores_agent() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.depositClaimBond{value: CLAIM_BOND}(1, agent);
        vm.stopPrank();

        (, uint256 bond, address storedAgent) = escrow.getEntry(1);
        assertEq(bond, CLAIM_BOND);
        assertEq(storedAgent, agent);
    }

    function test_deposit_claim_bond_reverts_no_bounty() public {
        vm.prank(registry);
        vm.expectRevert(BountyEscrow.NoBounty.selector);
        escrow.depositClaimBond{value: CLAIM_BOND}(99, agent);
    }

    // ─── settleSuccess ────────────────────────────────────────────────────────

    function test_settle_success_pays_agent() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.depositClaimBond{value: CLAIM_BOND}(1, agent);
        vm.stopPrank();

        uint256 balBefore = agent.balance;

        vm.prank(registry);
        escrow.settleSuccess(1, agent);

        assertEq(agent.balance, balBefore + BOUNTY + CLAIM_BOND);
    }

    function test_settle_success_clears_entry() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.depositClaimBond{value: CLAIM_BOND}(1, agent);
        escrow.settleSuccess(1, agent);
        vm.stopPrank();

        (uint256 bounty, uint256 bond,) = escrow.getEntry(1);
        assertEq(bounty, 0);
        assertEq(bond, 0);
    }

    function test_settle_success_emits_events() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.depositClaimBond{value: CLAIM_BOND}(1, agent);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit ClaimBondReturned(1, agent, CLAIM_BOND);
        vm.expectEmit(true, true, false, true);
        emit BountyReleased(1, agent, BOUNTY);

        vm.prank(registry);
        escrow.settleSuccess(1, agent);
    }

    function test_settle_success_reverts_no_bounty() public {
        vm.prank(registry);
        vm.expectRevert(BountyEscrow.NoBounty.selector);
        escrow.settleSuccess(99, agent);
    }

    // ─── forfeitBond ─────────────────────────────────────────────────────────

    function test_forfeit_bond_sends_to_treasury() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.depositClaimBond{value: CLAIM_BOND}(1, agent);
        escrow.forfeitBond(1);
        vm.stopPrank();

        assertEq(treasury.balance, CLAIM_BOND);
    }

    function test_forfeit_bond_keeps_bounty_locked() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.depositClaimBond{value: CLAIM_BOND}(1, agent);
        escrow.forfeitBond(1);
        vm.stopPrank();

        (uint256 bounty,,) = escrow.getEntry(1);
        assertEq(bounty, BOUNTY);
    }

    function test_forfeit_bond_clears_agent_slot() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.depositClaimBond{value: CLAIM_BOND}(1, agent);
        escrow.forfeitBond(1);
        vm.stopPrank();

        (, uint256 bond, address storedAgent) = escrow.getEntry(1);
        assertEq(bond, 0);
        assertEq(storedAgent, address(0));
    }

    function test_forfeit_bond_reverts_no_bond() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        vm.expectRevert(BountyEscrow.NoBond.selector);
        escrow.forfeitBond(1);
        vm.stopPrank();
    }

    function test_forfeit_bond_emits_event() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.depositClaimBond{value: CLAIM_BOND}(1, agent);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit ClaimBondForfeited(1, agent, CLAIM_BOND);

        vm.prank(registry);
        escrow.forfeitBond(1);
    }

    // ─── refundBounty ─────────────────────────────────────────────────────────

    function test_refund_bounty_returns_to_poster() public {
        vm.prank(registry);
        escrow.depositBounty{value: BOUNTY}(1);

        uint256 balBefore = poster.balance;

        vm.prank(registry);
        escrow.refundBounty(1, poster);

        assertEq(poster.balance, balBefore + BOUNTY);
    }

    function test_refund_bounty_clears_entry() public {
        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(1);
        escrow.refundBounty(1, poster);
        vm.stopPrank();

        (uint256 bounty,,) = escrow.getEntry(1);
        assertEq(bounty, 0);
    }

    function test_refund_bounty_reverts_no_bounty() public {
        vm.prank(registry);
        vm.expectRevert(BountyEscrow.NoBounty.selector);
        escrow.refundBounty(99, poster);
    }

    function test_refund_bounty_emits_event() public {
        vm.prank(registry);
        escrow.depositBounty{value: BOUNTY}(1);

        vm.expectEmit(true, true, false, true);
        emit BountyRefunded(1, poster, BOUNTY);

        vm.prank(registry);
        escrow.refundBounty(1, poster);
    }

    // ─── Reentrancy ───────────────────────────────────────────────────────────

    function test_reentrancy_guard_on_settle() public {
        ReentrantAttacker attacker = new ReentrantAttacker(address(escrow));
        vm.deal(address(attacker), 1 ether);

        vm.startPrank(registry);
        escrow.depositBounty{value: BOUNTY}(42);
        escrow.depositClaimBond{value: CLAIM_BOND}(42, address(attacker));
        vm.stopPrank();

        attacker.arm(42);

        // The attacker's receive() will try to re-enter; ReentrancyGuard should block it
        // The outer call should still succeed (attacker just fails to re-enter)
        vm.prank(registry);
        escrow.settleSuccess(42, address(attacker));

        // Verify funds were transferred exactly once
        assertEq(address(attacker).balance, 1 ether + BOUNTY + CLAIM_BOND);
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_settle_pays_exact_amounts(uint256 bounty, uint256 bond) public {
        bounty = bound(bounty, 1, 100 ether);
        bond   = bound(bond,   0, 1 ether);
        vm.deal(registry, bounty + bond + 1 ether);

        vm.startPrank(registry);
        escrow.depositBounty{value: bounty}(1);
        if (bond > 0) escrow.depositClaimBond{value: bond}(1, agent);
        vm.stopPrank();

        uint256 balBefore = agent.balance;

        vm.prank(registry);
        escrow.settleSuccess(1, agent);

        assertEq(agent.balance, balBefore + bounty + bond);
    }
}
