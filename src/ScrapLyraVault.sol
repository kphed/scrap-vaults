// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {Errors} from "src/utils/Errors.sol";
import {ScrapLyraVaultShare} from "src/ScrapLyraVaultShare.sol";

contract ScrapLyraVault is Errors, Owned {
    struct LiquidityPool {
        uint96 createdAt;
        address quoteAsset;
        ScrapLyraVaultShare share;
    }

    mapping(address => LiquidityPool) public liquidityPools;

    event SetLiquidityPool(address indexed liquidityPool);

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

        liquidityPools[liquidityPool] = LiquidityPool(
            SafeCastLib.safeCastTo96(block.timestamp),
            ILiquidityPool(liquidityPool).quoteAsset(),
            new ScrapLyraVaultShare(owner, shareUri)
        );

        emit SetLiquidityPool(liquidityPool);
    }
}
