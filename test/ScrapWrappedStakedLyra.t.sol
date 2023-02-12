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
            : amount.mulDivDown(assetsAfter, supplyAfter);

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
}
