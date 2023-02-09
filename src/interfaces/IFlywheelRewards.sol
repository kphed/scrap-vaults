// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface IFlywheelRewards {
    function getAccruedRewards(
        ERC20 strategy,
        uint32 lastUpdatedTimestamp
    ) external returns (uint256 rewards);

    function rewardToken() external view returns (ERC20);
}
