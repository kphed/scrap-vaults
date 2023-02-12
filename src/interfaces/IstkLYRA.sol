// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IstkLYRA {
    function getTotalRewardsBalance(address) external view returns (uint256);

    function claimRewards(address, uint256) external;

    function stake(address, uint256) external;
}
