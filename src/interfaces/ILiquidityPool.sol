pragma solidity 0.8.18;

interface ILiquidityPool {
    struct LiquidityPoolParameters {
        uint256 minDepositWithdraw;
        uint256 depositDelay;
        uint256 withdrawalDelay;
        uint256 withdrawalFee;
        address guardianMultisig;
        uint256 guardianDelay;
        uint256 adjustmentNetScalingFactor;
        uint256 callCollatScalingFactor;
        uint256 putCollatScalingFactor;
    }

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

    function getTokenPrice() external view returns (uint256);

    function queuedDepositHead() external view returns (uint256);

    function getLpParams()
        external
        view
        returns (LiquidityPoolParameters memory);
}
