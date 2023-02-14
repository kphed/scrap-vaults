// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICurveFactory {
    function deploy_pool(
        string memory,
        string memory,
        address[2] memory,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    ) external returns (address);
}
