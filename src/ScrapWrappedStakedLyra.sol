// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

interface IStkLyra {
    function getTotalRewardsBalance(address) external view returns (uint256);

    function claimRewards(address, uint256) external;
}

contract ScrapWrappedStakedLyra is ReentrancyGuard, Owned, ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    IStkLyra public constant STK_LYRA =
        IStkLyra(0xCb9f85730f57732fc899fb158164b9Ed60c77D49);

    uint256 public constant FEE_BASE = 10_000;
    uint256 public constant MAX_FEE = 1_000;

    // All fees go directly to the wstkLYRA/LYRA liquidity pool
    uint256 public REWARD_FEE = 500;

    event SetRewardFee(uint256);

    constructor(
        address _owner
    )
        Owned(_owner)
        ERC4626(
            ERC20(address(STK_LYRA)),
            "Scrap.sh | Wrapped Staked Lyra",
            "wstkLYRA"
        )
    {}

    function setRewardFee(uint256 fee) external onlyOwner {
        // If fee exceeds max, set it to the max fee
        REWARD_FEE = fee > MAX_FEE ? MAX_FEE : fee;

        emit SetRewardFee(fee);
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _claimRewards() private {
        uint256 rewards = STK_LYRA.getTotalRewardsBalance(address(this));

        STK_LYRA.claimRewards(address(this), rewards);

        uint256 rewardFee = rewards.mulDivDown(REWARD_FEE, FEE_BASE);

        if (rewardFee == 0) return;

        // Mint wstkLYRA against the newly-claimed rewards, and add them to the LP
        _mint(
            address(this),
            // Modified `convertToShares` logic with the assumption that totalSupply is
            // always non-zero, and with the reward fee amount deducted from total assets
            rewardFee.mulDivDown(totalSupply, totalAssets() - rewardFee)
        );

        // TODO: Add liquidity to the LP, transfer LP tokens to the owner
        // TODO: Max approve wstkLYRA @ the LP contract
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
