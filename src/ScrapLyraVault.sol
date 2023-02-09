// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ILiquidityToken} from "src/interfaces/ILiquidityToken.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {Errors} from "src/utils/Errors.sol";
import {ScrapLyraVaultShareERC1155} from "src/ScrapLyraVaultShareERC1155.sol";
import {IFlywheelRewards} from "src/interfaces/IFlywheelRewards.sol";
import {IMultiDistributor} from "src/interfaces/IMultiDistributor.sol";

contract ScrapLyraVault is Errors, Owned, ReentrancyGuard, ERC20 {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    struct RewardsState {
        uint224 index;
        uint32 lastUpdatedTimestamp;
    }

    uint224 public constant ONE = 1e18;
    ERC20 public constant STK_LYRA =
        ERC20(0x5B237ab26CeD47Fb8ED104671819C801Aa5bA45E);
    IMultiDistributor public constant MULTI_DISTRIBUTOR =
        IMultiDistributor(address(0));

    ILiquidityToken public immutable liquidityToken;
    ILiquidityPool public immutable liquidityPool;
    ERC20 public immutable quoteAsset;
    ScrapLyraVaultShareERC1155 public immutable depositShare;
    ScrapLyraVaultShareERC1155 public immutable withdrawShare;

    RewardsState public strategyState;
    mapping(address => uint224) public userIndex;
    mapping(address => uint256) public rewardsAccrued;

    event Deposit(
        address indexed msgSender,
        address indexed receiver,
        uint256 indexed queuedDepositId,
        uint256 amount,
        uint256 shareAmount
    );
    event AccrueRewards(
        address indexed user,
        uint256 rewardsDelta,
        uint256 rewardsIndex
    );
    event ClaimRewards(address indexed user, uint256 amount);

    error InvalidQueuedDeposit(
        uint256 queuedDepositId,
        uint256 amountLiquidity,
        uint256 depositInitiatedTime,
        ILiquidityPool.QueuedDeposit
    );

    constructor(
        ILiquidityToken _liquidityToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) Owned(msg.sender) ERC20(_name, _symbol, _decimals) {
        if (address(_liquidityToken) == address(0)) revert Zero();

        liquidityToken = _liquidityToken;
        liquidityPool = ILiquidityPool(liquidityToken.liquidityPool());
        quoteAsset = ERC20(liquidityPool.quoteAsset());
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

    function _getAccruedRewards() private returns (uint256) {
        uint256 balanceBeforeClaim = STK_LYRA.balanceOf(address(this));
        IERC20[] memory claimTokens = new IERC20[](1);
        claimTokens[0] = IERC20(address(STK_LYRA));

        MULTI_DISTRIBUTOR.claim(claimTokens);

        return STK_LYRA.balanceOf(address(this)) - balanceBeforeClaim;
    }

    function _accrueStrategy(
        RewardsState memory state
    ) private returns (RewardsState memory rewardsState) {
        uint256 strategyRewardsAccrued = _getAccruedRewards();

        rewardsState = state;

        if (strategyRewardsAccrued > 0) {
            uint256 supplyTokens = totalSupply;
            uint224 deltaIndex;

            if (supplyTokens != 0)
                deltaIndex = ((strategyRewardsAccrued * ONE) / supplyTokens)
                    .safeCastTo224();

            rewardsState = RewardsState({
                index: state.index + deltaIndex,
                lastUpdatedTimestamp: block.timestamp.safeCastTo32()
            });
            strategyState = rewardsState;
        }
    }

    function _accrueUser(
        address user,
        RewardsState memory state
    ) private returns (uint256) {
        uint224 strategyIndex = state.index;
        uint224 supplierIndex = userIndex[user];
        userIndex[user] = strategyIndex;

        if (supplierIndex == 0) supplierIndex = ONE;

        uint224 deltaIndex = strategyIndex - supplierIndex;
        uint256 supplierTokens = balanceOf[user];
        uint256 supplierDelta = (supplierTokens * deltaIndex) / ONE;
        uint256 supplierAccrued = rewardsAccrued[user] + supplierDelta;
        rewardsAccrued[user] = supplierAccrued;

        emit AccrueRewards(user, supplierDelta, strategyIndex);

        return supplierAccrued;
    }

    function _accrue(address user) private returns (uint256) {
        RewardsState memory state = strategyState;

        if (state.index == 0) return 0;

        state = _accrueStrategy(state);

        return _accrueUser(user, state);
    }

    function _accrue(
        address user,
        address secondUser
    ) private returns (uint256, uint256) {
        RewardsState memory state = strategyState;

        if (state.index == 0) return (0, 0);

        state = _accrueStrategy(state);

        return (_accrueUser(user, state), _accrueUser(secondUser, state));
    }

    function _accrueMint(address _to, uint256 _amount) private {
        _accrue(_to);
        _mint(_to, _amount);
    }

    function _accrueBurn(address _from, uint256 _amount) private {
        _accrue(_from);
        _burn(_from, _amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        if (to == address(0)) revert Zero();
        if (amount == 0) revert Zero();

        _accrue(msg.sender, to);

        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        if (from == address(0)) revert Zero();
        if (to == address(0)) revert Zero();
        if (amount == 0) revert Zero();

        _accrue(from, to);

        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    function claimRewards() external nonReentrant {
        if (msg.sender == address(0)) revert Zero();

        // Ensure accrued rewards are up-to-date prior to claiming
        uint256 accrued = _accrue(msg.sender);

        if (accrued != 0) {
            rewardsAccrued[msg.sender] = 0;

            STK_LYRA.safeTransfer(msg.sender, accrued);

            emit ClaimRewards(msg.sender, accrued);
        }
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
            _accrueMint(receiver, liquidityTokensMinted);

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
