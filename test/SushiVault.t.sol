// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SushiDeployment} from "src/SushiDeployment.sol";
import {Vault} from "src/Vault.sol";
import {SushiHelper, IUniswapV2Router02, IUniswapV2Pair} from "test/SushiHelper.sol";

contract SushiVaultTest is Test, SushiHelper {
    IUniswapV2Router02 public constant SUSHI_ROUTER =
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IUniswapV2Pair public constant SUSHI_LP =
        IUniswapV2Pair(0x905dfCD5649217c42684f23958568e533C711Aa3);

    Vault public immutable vault;

    constructor() {
        SushiDeployment deployment = new SushiDeployment(
            ERC20(address(SUSHI_LP)),
            "Scrap x Sushi | ETH-USDC",
            "scrapSushi-ETH-USDC"
        );
        vault = deployment.vault();
    }
}
