// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Helper} from "test/Helper.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ScrapWrappedStakedLyra} from "src/ScrapWrappedStakedLyra.sol";
import {IstkLYRA} from "src/interfaces/IstkLYRA.sol";
import {ICurveFactory} from "test/interfaces/ICurveFactory.sol";
import {ICryptoPool} from "test/interfaces/ICryptoPool.sol";

contract ScrapWrappedStakedLyraTest is Helper {
    using FixedPointMathLib for uint256;

    ICurveFactory private constant curveFactory =
        ICurveFactory(0xF18056Bbd320E96A48e3Fbf8bC061322531aac99);

    ScrapWrappedStakedLyra private immutable vault =
        new ScrapWrappedStakedLyra(address(this));

    ICryptoPool private immutable curvePool;
    ERC20 private immutable lyra;
    ERC20 private immutable stkLYRA;

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event SetLiquidityFee(uint256);
    event SetLiquidityPool(address);

    constructor() {
        address[2] memory coins = [
            0x01BA67AAC7f75f647D94220Cc98FB30FCc5105Bf,
            address(vault)
        ];

        vault.setLiquidityPool(
            curveFactory.deploy_pool(
                "Curve.fi LYRA/wsLYRA",
                "wsLYRACRV",
                coins,
                400000,
                145000000000000,
                26000000,
                45000000,
                2000000000000,
                230000000000000,
                146000000000000,
                5000000000,
                600,
                1100000000000000000
            )
        );

        curvePool = ICryptoPool(vault.liquidityPool());
        lyra = vault.LYRA();
        stkLYRA = ERC20(address(vault.STK_LYRA()));

        _seedVault();
        _seedPool();
        _provisionVault();
    }

    function _seedVault() private {
        uint256 amount = 1e18;

        _getStkLYRA(address(this), amount);

        stkLYRA.approve(address(vault), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(vault));

        emit Deposit(address(this), address(this), amount, amount);

        vault.deposit(amount, address(this));

        assertEq(vault.totalSupply(), 1e18);
        assertEq(vault.totalAssets(), 1e18);
    }

    function _seedPool() private {
        uint256 lyraAmount = 10_000e18;
        uint256 wstkAmount = 11_000e18;

        _getLYRA(address(this), lyraAmount);
        _getWStkLYRA(address(this), wstkAmount);

        lyra.approve(address(curvePool), lyraAmount);
        vault.approve(address(curvePool), wstkAmount);

        curvePool.add_liquidity([lyraAmount, wstkAmount], 0);

        assertLt(0, ERC20(curvePool.token()).balanceOf(address(this)));
    }

    function _getLYRA(address to, uint256 amount) private {
        address msig = 0x246d38588b16Dd877c558b245e6D5a711C649fCF;
        uint256 balanceBefore = lyra.balanceOf(to);

        vm.startPrank(msig);

        lyra.transfer(to, amount);

        vm.stopPrank();

        assertEq(balanceBefore + amount, lyra.balanceOf(to));
    }

    function _getStkLYRA(address to, uint256 amount) private {
        _getLYRA(to, amount);

        address _stkLYRA = address(vault.STK_LYRA());

        vm.startPrank(to);

        lyra.approve(_stkLYRA, type(uint256).max);

        IstkLYRA(_stkLYRA).stake(to, amount);

        vm.stopPrank();
    }

    function _checkDepositEvent(
        address caller,
        address owner,
        uint256 assets
    ) private {
        (uint256 assetsAfter, uint256 supplyAfter) = vault.totalsAfterRewards();
        uint256 shares = assets.mulDivDown(supplyAfter, assetsAfter);

        vm.expectEmit(true, true, false, true, address(vault));

        emit Deposit(caller, owner, assets, shares);
    }

    function _getWStkLYRA(address to, uint256 amount) private {
        uint256 balanceBefore = vault.balanceOf(to);
        (uint256 assetsAfter, uint256 supplyAfter) = vault.totalsAfterRewards();
        uint256 assets = supplyAfter == 0
            ? amount
            : amount.mulDivUp(assetsAfter, supplyAfter);

        _getStkLYRA(to, assets);

        vm.startPrank(to);

        stkLYRA.approve(address(vault), type(uint256).max);

        _checkDepositEvent(to, to, assets);

        vault.deposit(assets, to);

        vm.stopPrank();

        assertEq(balanceBefore + amount, vault.balanceOf(to));
    }

    function _provisionVault() private {
        uint256 baseAmount = 10e18;

        for (uint256 i; i < testAccLen; ) {
            address acc = testAcc[i];
            uint256 assets = baseAmount + (block.timestamp * (i + 1));
            bool depositLYRA = assets % 2 == 0;

            if (depositLYRA) {
                _getLYRA(acc, assets);

                vm.startPrank(acc);

                lyra.approve(address(vault), type(uint256).max);

                _checkDepositEvent(acc, acc, assets);

                vault.depositLYRA(assets, acc);

                vm.stopPrank();
            } else {
                _getStkLYRA(acc, assets);

                vm.startPrank(acc);

                stkLYRA.approve(address(vault), type(uint256).max);

                _checkDepositEvent(acc, acc, assets);

                vault.deposit(assets, acc);

                vm.stopPrank();
            }

            vm.warp(block.timestamp + (1_000 * (i + 1)));

            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        setLiquidityFee TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSetLiquidityFeeUnauthorized() external {
        uint256 fee = 1;

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(address(0));

        vault.setLiquidityFee(fee);
    }

    function testSetLiquidityFeeFuzz(uint16 fee) external {
        uint256 maxFee = vault.MAX_FEE();
        uint256 expectedFee = fee > maxFee ? maxFee : fee;

        vm.expectEmit(false, false, false, true, address(vault));

        emit SetLiquidityFee(expectedFee);

        vault.setLiquidityFee(expectedFee);

        assertEq(expectedFee, vault.liquidityFee());
    }

    /*//////////////////////////////////////////////////////////////
                        setLiquidityPool TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSetLiquidityPoolUnauthorized() external {
        address liquidityPool = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(address(0));

        vault.setLiquidityPool(liquidityPool);
    }

    function testCannotSetLiquidityPoolZeroAddress() external {
        address liquidityPool = address(0);

        vm.expectRevert(Zero.selector);

        vault.setLiquidityPool(liquidityPool);
    }

    function testSetLiquidityPool() public {
        address liquidityPool = address(this);

        vm.expectEmit(false, false, false, true, address(vault));

        emit SetLiquidityPool(liquidityPool);

        vault.setLiquidityPool(liquidityPool);

        assertEq(liquidityPool, vault.liquidityPool());
    }

    /*//////////////////////////////////////////////////////////////
                            depositLYRA TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotDepositLYRAZeroAmount() external {
        uint256 amount = 0;
        address receiver = address(this);

        vm.expectRevert(Zero.selector);

        vault.depositLYRA(amount, receiver);
    }

    function testCannotDepositLYRAZeroAddress() external {
        uint256 amount = 1e18;
        address receiver = address(0);

        vm.expectRevert(Zero.selector);

        vault.depositLYRA(amount, receiver);
    }

    function testCannotDepositLYRAInsufficientBalance() external {
        uint256 amount = 1e18;
        address receiver = address(this);

        _getLYRA(address(this), amount);

        lyra.approve(address(vault), amount);

        vm.expectRevert(TRANSFER_FROM_FAILED_ERROR);

        vault.depositLYRA(amount + 1, receiver);
    }

    function testDepositLYRA() external {
        uint256 amount = 1e18;
        address receiver = address(this);
        (uint256 assetsAfterRewards, uint256 supplyAfterRewards) = vault
            .totalsAfterRewards();
        uint256 shares = amount.mulDivDown(
            supplyAfterRewards,
            assetsAfterRewards
        );
        uint256 balanceBeforeDeposit = vault.balanceOf(receiver);

        _getLYRA(address(this), amount);

        lyra.approve(address(vault), amount);

        _checkDepositEvent(address(this), receiver, amount);

        vault.depositLYRA(amount, receiver);

        assertEq(assetsAfterRewards + amount, vault.totalAssets());
        assertEq(supplyAfterRewards + shares, vault.totalSupply());
        assertEq(balanceBeforeDeposit + shares, vault.balanceOf(receiver));
    }

    function testDepositLYRAFuzz(
        uint88 amount,
        bool separateReceiver
    ) external {
        vm.assume(amount > 1e9);
        vm.assume(amount < 10_000_000e18);

        address receiver = separateReceiver ? testAcc[0] : address(this);
        (uint256 assetsAfterRewards, uint256 supplyAfterRewards) = vault
            .totalsAfterRewards();
        uint256 shares = uint256(amount).mulDivDown(
            supplyAfterRewards,
            assetsAfterRewards
        );
        uint256 balanceBeforeDeposit = vault.balanceOf(receiver);

        _getLYRA(address(this), amount);

        lyra.approve(address(vault), amount);

        _checkDepositEvent(address(this), receiver, amount);

        vault.depositLYRA(amount, receiver);

        assertEq(assetsAfterRewards + amount, vault.totalAssets());
        assertEq(supplyAfterRewards + shares, vault.totalSupply());
        assertEq(balanceBeforeDeposit + shares, vault.balanceOf(receiver));
    }

    /*//////////////////////////////////////////////////////////////
                            deposit TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotDepositZeroAmount() external {
        uint256 assets = 0;
        address receiver = address(this);

        vm.expectRevert(Zero.selector);

        vault.deposit(assets, receiver);
    }

    function testCannotDepositZeroAddress() external {
        uint256 assets = 1e18;
        address receiver = address(0);

        vm.expectRevert(Zero.selector);

        vault.deposit(assets, receiver);
    }

    function testCannotDepositInsufficientBalance() external {
        uint256 assets = 1e18;
        address receiver = address(this);

        _getStkLYRA(address(this), assets);

        stkLYRA.approve(address(vault), assets);

        vm.expectRevert(TRANSFER_FROM_FAILED_ERROR);

        vault.deposit(assets + 1, receiver);
    }

    function testDeposit() external {
        uint256 assets = 1e18;
        address receiver = address(this);
        (uint256 assetsAfterRewards, uint256 supplyAfterRewards) = vault
            .totalsAfterRewards();
        uint256 shares = assets.mulDivDown(
            supplyAfterRewards,
            assetsAfterRewards
        );
        uint256 balanceBeforeDeposit = vault.balanceOf(receiver);

        _getStkLYRA(address(this), assets);

        stkLYRA.approve(address(vault), assets);

        _checkDepositEvent(address(this), receiver, assets);

        vault.deposit(assets, receiver);

        assertEq(assetsAfterRewards + assets, vault.totalAssets());
        assertEq(supplyAfterRewards + shares, vault.totalSupply());
        assertEq(balanceBeforeDeposit + shares, vault.balanceOf(receiver));
    }

    function testDepositFuzz(uint88 assets, bool separateReceiver) external {
        vm.assume(assets > 1e9);
        vm.assume(assets < 10_000_000e18);

        address receiver = separateReceiver ? testAcc[0] : address(this);
        (uint256 assetsAfterRewards, uint256 supplyAfterRewards) = vault
            .totalsAfterRewards();
        uint256 shares = uint256(assets).mulDivDown(
            supplyAfterRewards,
            assetsAfterRewards
        );
        uint256 balanceBeforeDeposit = vault.balanceOf(receiver);

        _getStkLYRA(address(this), assets);

        stkLYRA.approve(address(vault), assets);

        _checkDepositEvent(address(this), receiver, assets);

        vault.deposit(assets, receiver);

        assertEq(assetsAfterRewards + assets, vault.totalAssets());
        assertEq(supplyAfterRewards + shares, vault.totalSupply());
        assertEq(balanceBeforeDeposit + shares, vault.balanceOf(receiver));
    }

    /*//////////////////////////////////////////////////////////////
                                mint TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotMintZeroAmount() external {
        uint256 shares = 0;
        address receiver = address(this);

        vm.expectRevert(Zero.selector);

        vault.mint(shares, receiver);
    }

    function testCannotMintZeroAddress() external {
        uint256 shares = 1e18;
        address receiver = address(0);

        vm.expectRevert(Zero.selector);

        vault.mint(shares, receiver);
    }

    function testCannotMintInsufficientBalance() external {
        uint256 shares = 1e18;
        address receiver = address(this);
        (uint256 assetsAfterRewards, uint256 supplyAfterRewards) = vault
            .totalsAfterRewards();

        // Get the amount of necessary assets minus 1 (ensuring the error is triggered)
        uint256 assets = shares.mulDivUp(
            assetsAfterRewards,
            supplyAfterRewards
        ) - 10;

        _getStkLYRA(address(this), assets);

        stkLYRA.approve(address(vault), assets);

        vm.expectRevert(TRANSFER_FROM_FAILED_ERROR);

        vault.mint(shares, receiver);
    }

    function testMint() external {
        uint256 shares = 1e18;
        address receiver = address(this);
        (uint256 assetsAfterRewards, uint256 supplyAfterRewards) = vault
            .totalsAfterRewards();
        uint256 assets = shares.mulDivUp(
            assetsAfterRewards,
            supplyAfterRewards
        );
        uint256 balanceBeforeMint = vault.balanceOf(receiver);

        _getStkLYRA(address(this), assets);

        stkLYRA.approve(address(vault), assets);

        _checkDepositEvent(address(this), receiver, assets);

        vault.mint(shares, receiver);

        assertEq(assetsAfterRewards + assets, vault.totalAssets());
        assertEq(supplyAfterRewards + shares, vault.totalSupply());
        assertEq(balanceBeforeMint + shares, vault.balanceOf(receiver));
    }

    function testMintFuzz(uint88 shares, bool separateReceiver) external {
        vm.assume(shares > 1e9);
        vm.assume(shares < 10_000_000e18);

        address receiver = separateReceiver ? testAcc[0] : address(this);
        (uint256 assetsAfterRewards, uint256 supplyAfterRewards) = vault
            .totalsAfterRewards();
        uint256 assets = uint256(shares).mulDivUp(
            assetsAfterRewards,
            supplyAfterRewards
        );
        uint256 balanceBeforeMint = vault.balanceOf(receiver);

        _getStkLYRA(address(this), assets);

        stkLYRA.approve(address(vault), assets);

        _checkDepositEvent(address(this), receiver, assets);

        vault.mint(shares, receiver);

        assertEq(assetsAfterRewards + assets, vault.totalAssets());
        assertEq(supplyAfterRewards + shares, vault.totalSupply());
        assertEq(balanceBeforeMint + shares, vault.balanceOf(receiver));
    }
}
