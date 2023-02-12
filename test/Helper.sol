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

    uint256 internal immutable testAccLen;

    address[] internal testAcc = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
        0x90F79bf6EB2c4f870365E785982E1f101E93b906,
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
        0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
        0x976EA74026E726554dB657fA54763abd0C3a0aa9,
        0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
        0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
        0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
    ];

    constructor() {
        testAccLen = testAcc.length;
    }

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
