// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ArtemisStaking.sol";
import "../src/ArtemisERC20.sol";

contract ArtemisStakingTest is Test {
    ArtemisStaking staking;
    ArtemisERC20 stakingToken;
    address alice = address(0x1337);
    address bob = address(0x1234);

    function setUp() public {
        stakingToken = new ArtemisERC20("Artemis", "ART");
        staking = new ArtemisStaking(address(stakingToken), address(this));
        stakingToken.mint(address(this), type(uint104).max);
        stakingToken.mint(alice, 10000 * 1e18);
        stakingToken.mint(bob, 10000 * 1e18);
        stakingToken.approve(address(staking), type(uint256).max);
        vm.prank(alice);
        stakingToken.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        stakingToken.approve(address(staking), type(uint256).max);
    }

    function testFuzzStakingDeposit(uint104 amount) public {
        vm.assume(amount > 0);
        stakingToken.approve(address(staking), type(uint256).max);
        staking.deposit(amount);
        assertEq(amount, staking.balance(address(this)));
        assertEq(amount, staking.totalSupply());
    }

    function testDeposits2() public {
        staking.deposit(1000 * 1e18);
        vm.prank(alice);
        staking.deposit(1000 * 1e18);
        vm.prank(bob);
        staking.deposit(1000 * 1e18);
        assertEq(stakingToken.balanceOf(address(staking)), 3000 * 1e18);
        assertEq(staking.balance(alice), 1000 * 1e18);
        assertEq(staking.balance(bob), 1000 * 1e18);
        assertEq(staking.balance(address(this)), 1000 * 1e18);
        assertEq(staking.totalSupply(), 3000 * 1e18);
    }

    function testIssuanceRate() public {
        vm.expectRevert("Supply must be > 0");
        staking.issuanceRate(100 * 1e18);
        testDeposits2();
        vm.expectRevert(ArtemisStaking.NotOwner.selector);
        vm.prank(alice);
        staking.issuanceRate(100 * 1e18);
        vm.expectRevert("Rewards must be > 0");
        staking.issuanceRate(0);
        staking.issuanceRate(10000 * 1e18);
        uint256 time = 30 days;
        assertEq(staking.rewardRate(), (10000 * 1e18) / time);
        assertEq(stakingToken.balanceOf(address(staking)), 13000 * 1e18); //Must add previous deposits
        assertEq(staking.periodFinish(), block.timestamp + time);
        assertEq(staking.lastUpdateTime(), block.timestamp);
    }

    function testViewFunctions() public {
        testDeposits2();
        staking.issuanceRate(1000 * 1e18);
        uint256 expected = 1000 * 1e18;
        uint256 rewards = 0;
        uint256 dust = 1e10;
        assertEq(expected, staking.balance(address(this)));
        assertEq(staking.checkRewards(address(this)), rewards);
        assertGt(staking.getRewardForDuration(), 1000 * 1e18 - dust);
    }

    function testWithdraws() public {
        staking.deposit(1000 * 1e18);
        staking.issuanceRate(10000 * 1e18);
        vm.warp(31 days);
        staking.withdraw(1000 * 1e18);
        assertLt(stakingToken.balanceOf(address(staking)), 1e8);
        assertEq(staking.earned(address(this)), 0);
        assertEq(staking.totalSupply(), 0);
        assertEq(
            staking.rewardPerTokenStored(),
            staking.rewardPerTokenStored()
        );
        assertEq(staking.lastTimeRewardApplicable(), staking.periodFinish());
    }
}
