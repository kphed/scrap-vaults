// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILiquidityToken {
    function liquidityPool() external view returns (address);

    function balanceOf(address) external view returns (uint256);
}
