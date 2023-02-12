// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Errors} from "src/utils/Errors.sol";

interface IstkLYRA {
    function getTotalRewardsBalance(address) external view returns (uint256);

    function claimRewards(address, uint256) external;
}

contract ScrapWrappedStakedLyra is Errors, ReentrancyGuard, Owned, ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IstkLYRA public constant STK_LYRA =
        IstkLYRA(0xCb9f85730f57732fc899fb158164b9Ed60c77D49);
    uint256 public constant FEE_BASE = 10_000;

    // Maximum fee is 10% and can only be reduced from here
    uint256 public constant MAX_FEE = 1_000;

    // All fees are added to the LYRA/wsLYRA liquidity pool
    uint256 public liquidityFee = 1_000;

    address public liquidityPool;

    event SetRewardFee(uint256);
    event SetLiquidityPool(address);

    constructor(
        address _owner
    )
        Owned(_owner)
        ERC4626(
            ERC20(address(STK_LYRA)),
            "Scrap.sh Wrapped Staked LYRA",
            "wsLYRA"
        )
    {}

    function setRewardFee(uint256 fee) external onlyOwner {
        // If fee exceeds max, set it to the max fee
        liquidityFee = fee > MAX_FEE ? MAX_FEE : fee;

        emit SetRewardFee(fee);
    }

    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        if (_liquidityPool == address(0)) revert Zero();

        liquidityPool = _liquidityPool;

        emit SetLiquidityPool(_liquidityPool);
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _claimRewards() private {
        uint256 assetsBeforeClaim = asset.balanceOf(address(this));

        STK_LYRA.claimRewards(address(this), type(uint256).max);

        // Ensures that we are working with actual amount of rewards claimed
        uint256 assetsAfterClaim = asset.balanceOf(address(this));
        uint256 totalRewards = assetsAfterClaim - assetsBeforeClaim;
        uint256 protocolRewards = totalRewards.mulDivDown(
            liquidityFee,
            FEE_BASE
        );

        if (protocolRewards == 0) return;

        // Mint wsLYRA against the newly-claimed rewards, and add them to the liquidity pool
        // If the pool has not been set, mint the shares for the owner instead (who can add liquidity later)
        _mint(
            liquidityPool != address(0) ? liquidityPool : owner,
            // Modified `convertToShares` logic with the assumption that totalSupply is
            // always non-zero, and with the reward fee amount deducted from assets after claim
            protocolRewards.mulDivDown(
                totalSupply,
                assetsAfterClaim - protocolRewards
            )
        );
    }

    function claimRewards() external nonReentrant {
        _claimRewards();
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        _claimRewards();

        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        _claimRewards();

        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
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

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
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
}
