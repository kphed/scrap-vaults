// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";
import {Errors} from "src/utils/Errors.sol";
import {ILiquidityToken} from "src/interfaces/ILiquidityToken.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {ScrapLyraVault} from "src/ScrapLyraVault.sol";
import {ScrapLyraVaultShare} from "src/ScrapLyraVaultShare.sol";
import {ScrapLyraVaultShareERC1155} from "src/ScrapLyraVaultShareERC1155.sol";

contract ScrapLyraVaultTest is Errors, Test {
    ILiquidityToken private constant LYRA_USDC_LIQUIDITY_TOKEN =
        ILiquidityToken(0xBdF4E630ded14a129aE302f930D1Ae1B40fd02aa);
    ILiquidityPool private constant LYRA_USDC_LIQUIDITY_POOL =
        ILiquidityPool(0xB619913921356904Bf62abA7271E694FD95AA10D);

    bytes private constant UNAUTHORIZED_ERROR = bytes("UNAUTHORIZED");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    ScrapLyraVault private immutable vault = new ScrapLyraVault();

    event SetLiquidityToken(
        ILiquidityToken indexed liquidityToken,
        ILiquidityPool indexed pool,
        ERC20 indexed asset
    );

    function _hasRole(
        AccessControl accessControl,
        bytes32 role,
        address account
    ) internal view returns (bool) {
        return accessControl.hasRole(role, account);
    }

    /*//////////////////////////////////////////////////////////////
                        setLiquidityToken TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSetLiquidityTokenUnauthorized() external {
        ILiquidityToken liquidityToken = LYRA_USDC_LIQUIDITY_TOKEN;

        vm.prank(address(0));
        vm.expectRevert(UNAUTHORIZED_ERROR);

        vault.setLiquidityToken(liquidityToken);
    }

    function testCannotSetLiquidityTokenLiquidityTokenZero() external {
        ILiquidityToken liquidityToken = ILiquidityToken(address(0));

        vm.expectRevert(Zero.selector);

        vault.setLiquidityToken(liquidityToken);
    }

    function testCannotSetLiquidityTokenAlreadySet() external {
        ILiquidityToken liquidityToken = LYRA_USDC_LIQUIDITY_TOKEN;

        vault.setLiquidityToken(liquidityToken);

        vm.expectRevert(ScrapLyraVault.AlreadySet.selector);

        vault.setLiquidityToken(liquidityToken);
    }

    function testSetLiquidityToken() external {
        ILiquidityToken liquidityToken = LYRA_USDC_LIQUIDITY_TOKEN;
        ILiquidityPool pool = ILiquidityPool(liquidityToken.liquidityPool());
        ERC20 asset = ERC20(pool.quoteAsset());

        vm.expectEmit(true, true, true, true, address(vault));

        emit SetLiquidityToken(liquidityToken, pool, asset);

        vault.setLiquidityToken(liquidityToken);

        (
            ILiquidityPool _pool,
            ERC20 _asset,
            ScrapLyraVaultShare share,
            ScrapLyraVaultShareERC1155 depositShare,
            ScrapLyraVaultShareERC1155 withdrawShare
        ) = vault.liquidityTokens(liquidityToken);

        assertEq(address(pool), address(_pool));
        assertEq(address(asset), address(_asset));
        assertTrue(address(share) != address(0));
        assertTrue(_hasRole(depositShare, ADMIN_ROLE, address(this)));
        assertTrue(_hasRole(withdrawShare, ADMIN_ROLE, address(this)));
        assertTrue(_hasRole(depositShare, VAULT_ROLE, address(vault)));
        assertTrue(_hasRole(withdrawShare, VAULT_ROLE, address(vault)));
        assertTrue(depositShare.supportsInterface(type(IERC1155).interfaceId));
        assertTrue(withdrawShare.supportsInterface(type(IERC1155).interfaceId));
    }
}
