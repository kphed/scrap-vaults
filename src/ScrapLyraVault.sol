// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {Errors} from "src/utils/Errors.sol";
import {ScrapLyraVaultShare} from "src/ScrapLyraVaultShare.sol";

contract ScrapLyraVault is Errors, Owned {
    using SafeTransferLib for ERC20;

    struct LiquidityPool {
        uint96 createdAt;
        address quoteAsset;
        ScrapLyraVaultShare share;
    }

    mapping(address => LiquidityPool) public liquidityPools;

    event SetLiquidityPool(
        address indexed liquidityPool,
        address indexed quoteAsset
    );

    error AlreadySet();

    constructor() Owned(msg.sender) {}

    /**
     * @notice Set a Lyra liquidity pool with its quote asset and a newly-deployed vault share contract
     * @param liquidityPool  address  Liquidity pool address
     * @param shareUri       string   Vault share URI
     */
    function setLiquidityPool(
        address liquidityPool,
        string memory shareUri
    ) external onlyOwner {
        if (liquidityPool == address(0)) revert Zero();
        if (liquidityPools[liquidityPool].createdAt != 0) revert AlreadySet();

        address quoteAsset = ILiquidityPool(liquidityPool).quoteAsset();

        liquidityPools[liquidityPool] = LiquidityPool(
            SafeCastLib.safeCastTo96(block.timestamp),
            quoteAsset,
            new ScrapLyraVaultShare(owner, shareUri)
        );

        // Set an allowance for the liquidity pool to transfer quote asset during deposits
        ERC20(quoteAsset).safeApprove(liquidityPool, type(uint256).max);

        emit SetLiquidityPool(liquidityPool, quoteAsset);
    }
}
