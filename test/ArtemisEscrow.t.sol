// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/ArtemisEscrow.sol";
import "../src/ArtemisERC20.sol";
import "../src/mocks/MockERC20.sol";

contract ArtemisEscrowTest is Test {
    ArtemisERC20 aERC20;
    ArtemisEscrow escrow;
    MockDAI dai;
    MockLUSD lusd;
    address alice = address(0x1337);
    address bob = address(0x1234);
    address jim = address(0x5678);

    function setUp() public {
        aERC20 = new ArtemisERC20("ArtemisERC20", "ART");
        escrow = new ArtemisEscrow(address(this));
        dai = new MockDAI(1e40);
        lusd = new MockLUSD(1e40);
        vm.prank(jim);
        dai.mint(jim, 1e40);
        escrow.setWhitelistedDepositors(address(this), address(dai));
        escrow.setWhitelistedDepositors(jim, address(dai));
        escrow.setReceivers(bob);
        escrow.setReceivers(alice);

        aERC20.mint(address(this), 1e40);

        dai.approve(address(escrow), type(uint256).max);
        aERC20.approve(address(escrow), type(uint256).max);
        lusd.approve(address(escrow), type(uint256).max);

        vm.prank(jim);
        dai.approve(address(escrow), type(uint256).max);
    }

    // User Function Tests
    function testEscrowDeposit() public {
        escrow.deposit(address(dai), 10000 * 1e18);
        uint256 daiBalance = escrow.checkBalances(address(dai));
        uint256 user = escrow.userBalances(address(this));
        assertEq(dai.balanceOf(address(escrow)), 10000 * 1e18);
        assertEq(daiBalance, 10000 * 1e18);
        assertEq(user, 10000 * 1e18);
    }

    function testEscrowWithdraw() public {
        testEscrowDeposit();
        address token = escrow.tokens(0);
        escrow.pause();
        escrow.setPayout(500, alice);
        escrow.setPayout(500, bob);
        vm.prank(alice);
        escrow.withdraw(alice);
        vm.prank(bob);
        escrow.withdraw(bob);
        assertEq(dai.balanceOf(alice), 5000 * 1e18);
        assertEq(dai.balanceOf(bob), 5000 * 1e18);
        assertEq(dai.balanceOf(address(escrow)), 0);
        assertEq(token, address(dai));
    }

    function testEscrowDispute() public {
        testEscrowDeposit();
        escrow.wait(2 days);
        escrow.dispute();
        assertEq(escrow.underDispute(), true);

        escrow.settleDispute(false, address(dai));
        assertEq(dai.balanceOf(address(escrow)), 0);

        escrow.settleDispute(true, address(dai));
        assertEq(escrow.underDispute(), false);
    }

    // Owner Function Tests
    function testEscrowWhitelist() public {
        assertEq(escrow.whitelistedDepositors(address(this)), true);
        assertEq(escrow.tokens(0), address(dai));
        assertEq(escrow.whitelistedTokens(address(dai)), true);

        vm.expectRevert("Only the owner can call this function");
        vm.prank(alice);
        escrow.setWhitelistedDepositors(alice, address(dai));
    }

    function testEscrowReceivers() public {
        assertEq(escrow.receivers(alice), true);
        assertEq(escrow.receivers(bob), true);

        vm.expectRevert("Only the owner can call this function");
        vm.prank(alice);
        escrow.setReceivers(alice);
    }

    function testEscrowPayout() public {
        escrow.setPayout(500, alice);
        assertEq(escrow.payout(alice), 500);

        vm.expectRevert("Only the owner can call this function");
        vm.prank(alice);
        escrow.setPayout(500, alice);
    }

    function testEscrowWait() public {
        escrow.wait(2 days);
        assertEq(escrow.withdrawTime(), block.timestamp + 2 days);

        vm.expectRevert("Only the owner can call this function");
        vm.prank(alice);
        escrow.wait(2 days);
    }

    function testEscrowPause() public {
        vm.expectRevert("Pausable: not paused");
        vm.prank(alice);
        escrow.withdraw(alice);

        escrow.pause();

        vm.expectRevert("Pausable: paused");
        escrow.deposit(address(dai), 10000 * 1e18);
    }

    function testEscrowState() public {
        assertEq(escrow.tokens(0), address(dai));
        escrow.resetState();
        assertEq(escrow.tokens(0), address(0));
    }

    function testEscrowAccessControl() public {
        vm.expectRevert("Not depositor");
        vm.prank(alice);
        escrow.deposit(address(dai), 1000);

        escrow.pause();
        vm.expectRevert("Not Receiver");
        escrow.withdraw(address(this));

        escrow.wait(2 days);
        vm.expectRevert("Not Depositor");
        vm.prank(alice);
        escrow.dispute();
    }
}
