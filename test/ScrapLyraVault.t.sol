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

    ScrapLyraVault private immutable vault =
        new ScrapLyraVault(LYRA_USDC_LIQUIDITY_TOKEN);

    function _hasRole(
        AccessControl accessControl,
        bytes32 role,
        address account
    ) internal view returns (bool) {
        return accessControl.hasRole(role, account);
    }
}
