// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICryptoPool {
    function add_liquidity(uint256[2] memory, uint256) external payable;

    function coins(uint256 arg0) external view returns (address);

    function token() external view returns (address);

    function calc_token_amount(
        uint256[2] memory
    ) external view returns (uint256);
}
