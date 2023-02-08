// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

contract Address {
    function _addressToUint256(address addr) internal pure returns (uint256) {
        return uint256(uint160(addr));
    }

    function _uint256ToAddress(uint256 addr) internal pure returns (address) {
        return address(uint160(addr));
    }
}
