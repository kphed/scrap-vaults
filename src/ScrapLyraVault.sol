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

    ILiquidityToken public immutable liquidityToken;
    ILiquidityPool public immutable liquidityPool;
    ERC20 public immutable quoteAsset;
    ScrapLyraVaultShare public immutable share;
    ScrapLyraVaultShareERC1155 public immutable depositShare;
    ScrapLyraVaultShareERC1155 public immutable withdrawShare;

    event Deposit(
        address indexed msgSender,
        address indexed receiver,
        uint256 indexed queuedDepositId,
        uint256 amount,
        uint256 shareAmount
    );

    error InvalidQueuedDeposit(
        uint256 queuedDepositId,
        uint256 amountLiquidity,
        uint256 depositInitiatedTime,
        ILiquidityPool.QueuedDeposit
    );

    constructor(ILiquidityToken _liquidityToken) Owned(msg.sender) {
        if (address(_liquidityToken) == address(0)) revert Zero();

        liquidityToken = _liquidityToken;
        liquidityPool = ILiquidityPool(liquidityToken.liquidityPool());
        quoteAsset = ERC20(liquidityPool.quoteAsset());
        share = new ScrapLyraVaultShare("", "", 18, address(this));
        depositShare = new ScrapLyraVaultShareERC1155(
            msg.sender,
            address(this)
        );
        withdrawShare = new ScrapLyraVaultShareERC1155(
            msg.sender,
            address(this)
        );

        // Set an allowance for the liquidity pool to transfer asset during deposits
        quoteAsset.safeApprove(address(liquidityPool), type(uint256).max);
    }

    function _verifyQueuedDeposit(
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
            queuedDepositId,
            amountLiquidity,
            depositInitiatedTime,
            queuedDeposit
        );
    }

    /**
     * Deposit a Lyra liquidity pool quote asset for share tokens and earn rewards
     *
     * @param amount          uint256          Quote asset amount to deposit
     * @param receiver        address          Receiver of share tokens
     */
    function deposit(uint256 amount, address receiver) external nonReentrant {
        if (address(liquidityToken) == address(0)) revert Zero();
        if (amount == 0) revert Zero();

        // Reverts if liquidity token is not set
        quoteAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Enables us to determine the exact amount of liquidity tokens minted
        // in the event where there are zero live boards
        uint256 balanceBeforeInitiation = liquidityToken.balanceOf(
            address(this)
        );

        // Signal a deposit to the liquidity pool, which may mint liquidity token
        // or queue the deposit, depending on the state of the protocol
        liquidityPool.initiateDeposit(address(this), amount);

        uint256 liquidityTokensMinted = liquidityToken.balanceOf(
            address(this)
        ) - balanceBeforeInitiation;

        if (liquidityTokensMinted == 0) {
            // Get the ID of our recently queued deposit
            uint256 queuedDepositId = liquidityPool.nextQueuedDepositId() - 1;

            // Verify that the queued deposit is actually ours (sanity check)
            _verifyQueuedDeposit(queuedDepositId, amount, block.timestamp);

            // Mint deposit shares for the receiver, which accrues rewards but does
            // not allow the receiver to withdraw the underlying liquidity tokens
            depositShare.mint(receiver, queuedDepositId, amount, "");

            emit Deposit(msg.sender, receiver, amount, queuedDepositId, amount);
        } else {
            // Mint shares for the receiver if the liquidity was immediately added
            share.mint(receiver, liquidityTokensMinted);

            emit Deposit(
                msg.sender,
                receiver,
                amount,
                0,
                liquidityTokensMinted
            );
        }
    }
}
