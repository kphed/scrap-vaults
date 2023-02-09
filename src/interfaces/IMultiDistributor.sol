// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

interface IMultiDistributor {
    function claim(IERC20[] memory tokens) external;

    function claimableBalances(address, IERC20) external view returns (uint256);
}
