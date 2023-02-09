// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Errors} from "src/utils/Errors.sol";

contract ScrapLyraVaultShare is Errors, AccessControl, ERC20 {
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address vault
    ) ERC20(_name, _symbol, _decimals) {
        if (vault == address(0)) revert Zero();

        _setupRole(VAULT_ROLE, vault);
    }

    function mint(address _to, uint256 _amount) external onlyRole(VAULT_ROLE) {
        _mint(_to, _amount);
    }

    function burn(
        address _from,
        uint256 _amount
    ) external onlyRole(VAULT_ROLE) {
        _burn(_from, _amount);
    }
}
