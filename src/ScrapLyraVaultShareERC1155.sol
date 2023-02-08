// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC1155Supply} from "openzeppelin/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155} from "openzeppelin/token/ERC1155/ERC1155.sol";
import {Errors} from "src/utils/Errors.sol";

contract ScrapLyraVaultShareERC1155 is Errors, Owned, ERC1155Supply {
    constructor(address _owner) Owned(_owner) ERC1155("") {}

    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }
}