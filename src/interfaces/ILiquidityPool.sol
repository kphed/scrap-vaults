// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILiquidityPool {
    struct QueuedDeposit {
        uint256 id;
        address beneficiary;
        uint256 amountLiquidity;
        uint256 mintedTokens;
        uint256 depositInitiatedTime;
    }

    function initiateDeposit(address beneficiary, uint256 amountQuote) external;

    function processDepositQueue(uint256 limit) external;

    function quoteAsset() external view returns (address);

    function nextQueuedDepositId() external view returns (uint256);

    function queuedDeposits(
        uint256
    ) external view returns (QueuedDeposit memory);
}
