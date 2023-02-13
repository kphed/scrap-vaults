// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Errors} from "src/utils/Errors.sol";
import {IstkLYRA} from "src/interfaces/IstkLYRA.sol";

contract ScrapWrappedStakedLyra is Errors, ReentrancyGuard, Owned, ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IstkLYRA public constant STK_LYRA =
        IstkLYRA(0xCb9f85730f57732fc899fb158164b9Ed60c77D49);
    ERC20 public constant LYRA =
        ERC20(0x01BA67AAC7f75f647D94220Cc98FB30FCc5105Bf);
    uint256 public constant FEE_BASE = 10_000;

    // Maximum fee is 10% and can only be reduced from here
    uint256 public constant MAX_FEE = 1_000;

    // All fees are added to the LYRA/wsLYRA liquidity pool
    uint256 public liquidityFee = 1_000;

    address public liquidityPool;

    // Receives the wsLYRA liquidity fee and adds it to the LP via a separate process
    // aimed at mitigating front or back-running and with improved slippage control
    address public liquidityProvider;

    event SetLiquidityFee(uint256 liquidityFee);
    event SetLiquidityPool(address liquidityPool);
    event SetLiquidityProvider(address liquidityProvider);
    event ClaimRewards(
        uint256 claimableRewards,
        uint256 protocolRewards,
        uint256 liquidityShares
    );

    constructor(
        address _owner,
        address _liquidityProvider
    )
        Owned(_owner)
        ERC4626(
            ERC20(address(STK_LYRA)),
            "Scrap.sh Wrapped Staked LYRA",
            "wsLYRA"
        )
    {
        if (_owner == address(0)) revert Zero();
        if (_liquidityProvider == address(0)) revert Zero();

        // Pre-set an allowance to save gas and enable us to stake LYRA
        LYRA.safeApprove(address(STK_LYRA), type(uint256).max);

        liquidityProvider = _liquidityProvider;
    }

    function _claimRewards() private {
        uint256 claimableRewards = STK_LYRA.getTotalRewardsBalance(
            address(this)
        );
        uint256 protocolRewards = claimableRewards.mulDivDown(
            liquidityFee,
            FEE_BASE
        );

        if (protocolRewards == 0) return;

        STK_LYRA.claimRewards(address(this), claimableRewards);

        // Modified `convertToShares` logic with the liquidity fee deducted from assets
        uint256 liquidityShares = protocolRewards.mulDivDown(
            totalSupply,
            asset.balanceOf(address(this)) - protocolRewards
        );

        // Mint wsLYRA against the newly-claimed rewards, and add them to the liquidity pool
        _mint(
            // Mint wslYRA for the liquidity provider, who will add it to the LP
            liquidityProvider,
            liquidityShares
        );

        emit ClaimRewards(claimableRewards, protocolRewards, liquidityShares);
    }

    /**
     * Set the liquidity fee
     *
     * @param  _liquidityFee  uint256  Liquidity fee in BPS
     */
    function setLiquidityFee(uint256 _liquidityFee) external onlyOwner {
        // If fee exceeds max, set it to the max fee
        liquidityFee = _liquidityFee > MAX_FEE ? MAX_FEE : _liquidityFee;

        emit SetLiquidityFee(_liquidityFee);
    }

    /**
     * Set the liquidity pool
     *
     * @param  _liquidityPool  address  LYRA/wsLYRA LP contract address
     */
    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        if (_liquidityPool == address(0)) revert Zero();

        liquidityPool = _liquidityPool;

        emit SetLiquidityPool(_liquidityPool);
    }

    /**
     * Set the liquidity provider
     *
     * @param  _liquidityProvider  address  Account that adds wsLYRA to the LP
     */
    function setLiquidityProvider(
        address _liquidityProvider
    ) external onlyOwner {
        if (_liquidityProvider == address(0)) revert Zero();

        liquidityProvider = _liquidityProvider;

        emit SetLiquidityProvider(_liquidityProvider);
    }

    /**
     * Get the vault's stkLYRA balance
     *
     * @return uint256  Asset balance
     */
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * Get the stkLYRA balance and wsLYRA supply after rewards and fees are accounted for
     *
     * @return  assets  uint256  Post-reward stkLYRA balance
     * @return  supply  uint256  Post-reward wsLYRA supply
     */
    function totalsAfterRewards()
        external
        view
        returns (uint256 assets, uint256 supply)
    {
        assets = asset.balanceOf(address(this));
        supply = totalSupply;
        uint256 claimableRewards = STK_LYRA.getTotalRewardsBalance(
            address(this)
        );

        if (claimableRewards == 0) return (assets, supply);

        // Include claimable rewards in the total asset amount
        assets += claimableRewards;

        uint256 protocolRewards = claimableRewards.mulDivDown(
            liquidityFee,
            FEE_BASE
        );

        // Include the shares minted against the liquidity fee in the total supply amount
        supply += protocolRewards.mulDivDown(supply, assets - protocolRewards);
    }

    /**
     * Deposit LYRA for wsLYRA
     *
     * @param  amount    uint256  LYRA amount
     * @param  receiver  address  Receives wsLYRA
     * @return shares    uint256  wsLYRA amount
     */
    function depositLYRA(
        uint256 amount,
        address receiver
    ) external nonReentrant returns (uint256 shares) {
        if (amount == 0) revert Zero();
        if (receiver == address(0)) revert Zero();

        _claimRewards();

        LYRA.safeTransferFrom(msg.sender, address(this), amount);

        uint256 assetsBeforeStaking = asset.balanceOf(address(this));

        STK_LYRA.stake(address(this), amount);

        // Calculate the exact amount of stkLYRA deposited by msg.sender
        uint256 assets = asset.balanceOf(address(this)) - assetsBeforeStaking;

        // Calculate shares using the total assets amount with the new assets deducted
        shares = totalSupply == 0
            ? assets
            : assets.mulDivDown(totalSupply, assetsBeforeStaking);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * Deposit stkLYRA for wsLYRA
     *
     * @param  assets    uint256  stkLYRA amount
     * @param  receiver  address  Receives wsLYRA
     * @return shares    uint256  wsLYRA amount
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert Zero();
        if (receiver == address(0)) revert Zero();

        _claimRewards();

        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * Mint wsLYRA with stkLYRA
     *
     * @param  shares    uint256  wsLYRA amount
     * @param  receiver  address  Receives wsLYRA
     * @return assets    uint256  stkLYRA amount
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert Zero();
        if (receiver == address(0)) revert Zero();

        _claimRewards();

        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * Withdraw stkLYRA with wsLYRA
     *
     * @param  assets    uint256  stkLYRA amount
     * @param  receiver  address  Receives stkLYRA
     * @param  owner     address  wsLYRA owner
     * @return shares    uint256  wsLYRA amount
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert Zero();
        if (receiver == address(0)) revert Zero();
        if (owner == address(0)) revert Zero();

        _claimRewards();

        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /**
     * Redeem stkLYRA with wsLYRA
     *
     * @param  shares    uint256  wsLYRA amount
     * @param  receiver  address  Receives stkLYRA
     * @param  owner     address  wsLYRA owner
     * @return assets    uint256  stkLYRA amount
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert Zero();
        if (receiver == address(0)) revert Zero();
        if (owner == address(0)) revert Zero();

        _claimRewards();

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /**
     * Claim stkLYRA rewards
     */
    function claimRewards() external nonReentrant {
        _claimRewards();
    }
}
