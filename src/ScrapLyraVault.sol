// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ILiquidityToken} from "src/interfaces/ILiquidityToken.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {Errors} from "src/utils/Errors.sol";
import {ScrapLyraVaultShare} from "src/ScrapLyraVaultShare.sol";
import {ScrapLyraVaultShareERC1155} from "src/ScrapLyraVaultShareERC1155.sol";

contract ScrapLyraVault is Errors, Owned, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    struct LiquidityToken {
        ILiquidityPool pool;
        ERC20 asset;
        ScrapLyraVaultShare share;
        ScrapLyraVaultShareERC1155 depositShare;
        ScrapLyraVaultShareERC1155 withdrawalShare;
    }

    mapping(ILiquidityToken => LiquidityToken) public liquidityTokens;

    event SetLiquidityToken(
        ILiquidityToken indexed liquidityToken,
        ILiquidityPool indexed pool,
        ERC20 indexed asset
    );

    error AlreadySet();

    constructor() Owned(msg.sender) {}

    /**
     * @notice Set a Lyra liquidity pool with its quote asset and a newly-deployed vault share contract
     * @param liquidityToken  ILiquidityToken  Liquidity token contract interface
     */
    function setLiquidityToken(
        ILiquidityToken liquidityToken
    ) external onlyOwner {
        if (address(liquidityToken) == address(0)) revert Zero();

        LiquidityToken storage token = liquidityTokens[liquidityToken];

        if (address(token.pool) != address(0)) revert AlreadySet();

        ILiquidityPool pool = ILiquidityPool(liquidityToken.liquidityPool());
        ERC20 asset = ERC20(pool.quoteAsset());
        token.pool = pool;
        token.asset = asset;
        token.share = new ScrapLyraVaultShare("", "", 18);
        token.depositShare = new ScrapLyraVaultShareERC1155(msg.sender);
        token.withdrawalShare = new ScrapLyraVaultShareERC1155(msg.sender);

        // Set an allowance for the liquidity pool to transfer asset during deposits
        asset.safeApprove(address(pool), type(uint256).max);

        emit SetLiquidityToken(liquidityToken, pool, asset);
    }
}
