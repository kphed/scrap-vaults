// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGMXAdapter {
    enum PriceType {
        MIN_PRICE,
        MAX_PRICE,
        REFERENCE,
        FORCE_MIN,
        FORCE_MAX
    }

    struct MarketPricingParams {
        uint256 staticSwapFeeEstimate;
        uint256 gmxUsageThreshold;
        uint256 priceVarianceCBPercent;
        uint256 chainlinkStalenessCheck;
    }

    function marketPricingParams(
        address
    ) external view returns (MarketPricingParams memory);

    function setMarketPricingParams(
        address,
        MarketPricingParams memory
    ) external;

    function owner() external view returns (address);

    function getSpotPriceForMarket(
        address optionMarket,
        PriceType pricing
    ) external view returns (uint spotPrice);
}
