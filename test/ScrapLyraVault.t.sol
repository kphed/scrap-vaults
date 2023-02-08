// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Errors} from "src/utils/Errors.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {ScrapLyraVault} from "src/ScrapLyraVault.sol";
import {ScrapLyraVaultShare} from "src/ScrapLyraVaultShare.sol";

contract ScrapLyraVaultTest is Errors, Test {
    address private constant LYRA_USDC_LIQUIDITY_POOL =
        0xB619913921356904Bf62abA7271E694FD95AA10D;
    bytes private constant UNAUTHORIZED_ERROR = bytes("UNAUTHORIZED");

    ScrapLyraVault private immutable vault = new ScrapLyraVault();

    event SetLiquidityPool(
        address indexed liquidityPool,
        address indexed quoteAsset
    );

    /*//////////////////////////////////////////////////////////////
                        setLiquidityPool TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSetLiquidityPooUnauthorized() external {
        address liquidityPool = LYRA_USDC_LIQUIDITY_POOL;
        string memory shareUri = "";

        vm.prank(address(0));
        vm.expectRevert(UNAUTHORIZED_ERROR);

        vault.setLiquidityPool(liquidityPool, shareUri);
    }

    function testCannotSetLiquidityPoolLiquidityPoolZero() external {
        address liquidityPool = address(0);
        string memory shareUri = "";

        vm.expectRevert(Zero.selector);

        vault.setLiquidityPool(liquidityPool, shareUri);
    }

    function testCannotSetLiquidityPoolLiquidityPoolAlreadySet() external {
        address liquidityPool = LYRA_USDC_LIQUIDITY_POOL;
        string memory shareUri = "";

        vault.setLiquidityPool(liquidityPool, shareUri);

        vm.expectRevert(ScrapLyraVault.AlreadySet.selector);

        vault.setLiquidityPool(liquidityPool, shareUri);
    }

    function testSetLiquidityPool() external {
        address liquidityPool = LYRA_USDC_LIQUIDITY_POOL;
        string memory shareUri = "";

        vm.expectEmit(true, true, false, true, address(vault));

        emit SetLiquidityPool(
            liquidityPool,
            ILiquidityPool(liquidityPool).quoteAsset()
        );

        vault.setLiquidityPool(liquidityPool, shareUri);

        (
            uint96 createdAt,
            address quoteAsset,
            ScrapLyraVaultShare share
        ) = vault.liquidityPools(liquidityPool);

        assertEq(block.timestamp, createdAt);
        assertEq(ILiquidityPool(liquidityPool).quoteAsset(), quoteAsset);
        assertTrue(address(share) != address(0));
        assertEq(address(vault.owner()), share.owner());
    }
}
