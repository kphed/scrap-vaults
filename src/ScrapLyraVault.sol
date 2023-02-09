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
        ScrapLyraVaultShareERC1155 withdrawShare;
    }

    mapping(ILiquidityToken => LiquidityToken) public liquidityTokens;

    event SetLiquidityToken(
        ILiquidityToken indexed liquidityToken,
        ILiquidityPool indexed pool,
        ERC20 indexed asset
    );
    event Deposit(
        ILiquidityToken indexed liquidityToken,
        address indexed msgSender,
        address indexed receiver,
        uint256 queuedDepositId,
        uint256 amount,
        uint256 shareAmount
    );

    error AlreadySet();
    error InvalidQueuedDeposit(
        ILiquidityPool,
        uint256 queuedDepositId,
        uint256 amountLiquidity,
        uint256 depositInitiatedTime,
        ILiquidityPool.QueuedDeposit
    );

    constructor() Owned(msg.sender) {}

    function _verifyQueuedDeposit(
        ILiquidityPool liquidityPool,
        uint256 queuedDepositId,
        uint256 amountLiquidity,
        uint256 depositInitiatedTime
    ) private view {
        ILiquidityPool.QueuedDeposit memory queuedDeposit = liquidityPool
            .queuedDeposits(queuedDepositId);

        if (
            queuedDeposit.beneficiary == address(this) &&
            queuedDeposit.amountLiquidity == amountLiquidity &&
            queuedDeposit.depositInitiatedTime == depositInitiatedTime
        ) return;

        revert InvalidQueuedDeposit(
            liquidityPool,
            queuedDepositId,
            amountLiquidity,
            depositInitiatedTime,
            queuedDeposit
        );
    }

    /**
     * Set a Lyra liquidity token along with its associated pool and asset, and
     * deploy its share contracts
     *
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
        token.share = new ScrapLyraVaultShare("", "", 18, address(this));
        token.depositShare = new ScrapLyraVaultShareERC1155(
            msg.sender,
            address(this)
        );
        token.withdrawShare = new ScrapLyraVaultShareERC1155(
            msg.sender,
            address(this)
        );

        // Set an allowance for the liquidity pool to transfer asset during deposits
        asset.safeApprove(address(pool), type(uint256).max);

        emit SetLiquidityToken(liquidityToken, pool, asset);
    }

    /**
     * Deposit a Lyra liquidity pool quote asset for share tokens and earn rewards
     *
     * @param liquidityToken  ILiquidityToken  Liquidity token contract interface
     * @param amount          uint256          Quote asset amount to deposit
     * @param receiver        address          Receiver of share tokens
     */
    function deposit(
        ILiquidityToken liquidityToken,
        uint256 amount,
        address receiver
    ) external nonReentrant {
        if (address(liquidityToken) == address(0)) revert Zero();
        if (amount == 0) revert Zero();

        LiquidityToken memory token = liquidityTokens[liquidityToken];

        // Reverts if liquidity token is not set
        token.asset.safeTransferFrom(msg.sender, address(this), amount);

        // Enables us to determine the exact amount of liquidity tokens minted
        // in the event where there are zero live boards
        uint256 balanceBeforeInitiation = liquidityToken.balanceOf(
            address(this)
        );

        // Signal a deposit to the liquidity pool, which may mint liquidity token
        // or queue the deposit, depending on the state of the protocol
        token.pool.initiateDeposit(address(this), amount);

        uint256 liquidityTokensMinted = liquidityToken.balanceOf(
            address(this)
        ) - balanceBeforeInitiation;

        if (liquidityTokensMinted == 0) {
            // Get the ID of our recently queued deposit
            uint256 queuedDepositId = token.pool.nextQueuedDepositId() - 1;

            // Verify that the queued deposit is actually ours (sanity check)
            _verifyQueuedDeposit(
                token.pool,
                queuedDepositId,
                amount,
                block.timestamp
            );

            // Mint deposit shares for the receiver, which accrues rewards but does
            // not allow the receiver to withdraw the underlying liquidity tokens
            token.depositShare.mint(receiver, queuedDepositId, amount, "");

            emit Deposit(
                liquidityToken,
                msg.sender,
                receiver,
                amount,
                queuedDepositId,
                amount
            );
        } else {
            // Mint shares for the receiver if the liquidity was immediately added
            token.share.mint(receiver, liquidityTokensMinted);

            emit Deposit(
                liquidityToken,
                msg.sender,
                receiver,
                amount,
                0,
                liquidityTokensMinted
            );
        }
    }
}
