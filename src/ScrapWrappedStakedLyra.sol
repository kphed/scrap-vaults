// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

interface IStkLyra {
    function getTotalRewardsBalance(address) external view returns (uint256);
}

contract ScrapWrappedStakedLyra is ERC4626 {
    IStkLyra public constant STK_LYRA =
        IStkLyra(0xCb9f85730f57732fc899fb158164b9Ed60c77D49);

    constructor()
        ERC4626(
            ERC20(address(STK_LYRA)),
            "Scrap | Wrapped Staked Lyra",
            "wstkLYRA"
        )
    {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
