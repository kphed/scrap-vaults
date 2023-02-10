// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

interface IStkLyra {
    function getTotalRewardsBalance(address) external view returns (uint256);

    function claimRewards(address, uint256) external;
}

contract ScrapWrappedStakedLyra is ReentrancyGuard, ERC4626 {
    using SafeTransferLib for ERC20;

    IStkLyra public constant STK_LYRA =
        IStkLyra(0xCb9f85730f57732fc899fb158164b9Ed60c77D49);

    constructor()
        ERC4626(
            ERC20(address(STK_LYRA)),
            "Scrap.sh | Wrapped Staked Lyra",
            "wstkLYRA"
        )
    {}

    function totalAssets() public view override returns (uint256) {
        return
            asset.balanceOf(address(this)) +
            // Include the total rewards balance in the total assets amounts
            // since rewards are claimed prior to deposits or withdrawals
            STK_LYRA.getTotalRewardsBalance(address(this));
    }

    function _claimRewards() private {
        uint256 rewards = STK_LYRA.getTotalRewardsBalance(address(this));

        STK_LYRA.claimRewards(address(this), rewards);
    }

    function claimRewards() external nonReentrant {
        _claimRewards();
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        _claimRewards();

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        _claimRewards();

        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
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

        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

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
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }
}
