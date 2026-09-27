// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("oenwer");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmt) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmt}("");
    }

    function testCheckWhetherInterestIsGrowingOrNot(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        //  1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        uint256 startingBalance = rebaseToken.balanceOf(user);
        assertEq(startingBalance, amount);

        // move the time forward
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startingBalance);

        // move again the time forward
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startingBalance, 1);
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        // 1. deposit
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        // 2. redeem
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testDepositAndRedeemAfterSomeTime(uint256 amount, uint256 time) public {
        time = bound(time, 1000, 365 days);
        amount = bound(amount, 1e5, 1000 ether);

        vm.deal(user, amount);
        vm.prank(user);
        // 1 . deposit
        vault.deposit{value: amount}();

        //2.  warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterTime = rebaseToken.balanceOf(user);

        // Add rewards to the vault
        vm.deal(owner, balanceAfterTime - amount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterTime - amount);

        // 3. redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);
        vm.stopPrank();

        uint256 ethBalanceAfterRedeem = address(user).balance;
        assertEq(ethBalanceAfterRedeem, balanceAfterTime);
        assertGt(ethBalanceAfterRedeem, amount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");

        uint256 balanceOfUser = rebaseToken.balanceOf(user);
        uint256 balanceOfUser2 = rebaseToken.balanceOf(user2);

        // check the balance of user and user2 before transfer
        assertEq(balanceOfUser, amount);
        assertEq(balanceOfUser2, 0);

        // Decrease the Interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 balanceOfUserAfterTransfer = rebaseToken.balanceOf(user);
        uint256 balanceOfUser2AfterTransfer = rebaseToken.balanceOf(user2);

        // check the balance of user after transfer
        assertEq(balanceOfUserAfterTransfer, amount - amountToSend);
        assertEq(balanceOfUser2AfterTransfer, amountToSend);

        // check the interest rate  of both the users
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);

        // check interest rate After second time deposit
        vm.deal(user, 1 ether);
        vm.prank(user);
        vault.deposit{value: 1 ether}();
        assertEq(rebaseToken.getUserInterestRate(user), 4e10);
    }

    function testNormalUserCannotSetInterestRate() public {
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(1e10);
    }

    function testOtherThanVaultCannotCallMintAndBurn() public {
        uint256 interestRate = IRebaseToken(address(rebaseToken)).getProtocolsCurrentInterestRate();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, rebaseToken.getMintAndBurnRole()
            )
        );
        vm.prank(user);
        rebaseToken.mint(user, 1e18, interestRate);
    }

    function testgetPrincipleBalance(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.getUserPrincipleBalance(user), amount);
    }

    function testgetUserInterestRate(uint256 amount) public {
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
    }

    function testRevertsIfOwnerSetsHighInterestRate(uint256 newInterestRate) public {
        newInterestRate = bound(newInterestRate, rebaseToken.getProtocolsCurrentInterestRate(), type(uint96).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector,
                rebaseToken.getProtocolsCurrentInterestRate(),
                newInterestRate
            )
        );
        vm.prank(owner);
        rebaseToken.setInterestRate(newInterestRate);
    }
}
