// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Errors} from "src/utils/Errors.sol";

interface IUSDC {
    function gatewayAddress() external view returns (address);

    function bridgeMint(address to, uint256 amount) external;
}

contract Helper is Test, Errors {
    address internal constant USDC_ADDR =
        0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    IUSDC internal constant _USDC = IUSDC(USDC_ADDR);
    ERC20 internal constant USDC = ERC20(USDC_ADDR);

    function _hasRole(
        AccessControl accessControl,
        bytes32 role,
        address account
    ) internal view returns (bool) {
        return accessControl.hasRole(role, account);
    }

    function _mintUsdc(address to, uint256 amount) internal {
        uint256 preMintBalance = USDC.balanceOf(to);

        vm.startPrank(_USDC.gatewayAddress());

        _USDC.bridgeMint(to, amount);

        vm.stopPrank();

        assertEq(preMintBalance + amount, USDC.balanceOf(to));
    }
}
