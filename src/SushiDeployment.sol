// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Vault} from "src/Vault.sol";

contract SushiDeployment {
    Vault public immutable vault;

    constructor(ERC20 _asset, string memory _name, string memory _symbol) {
        vault = new Vault(_asset, _name, _symbol);
    }
}
