// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Owned} from "solmate/auth/Owned.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {ERC1155Supply} from "openzeppelin/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155} from "openzeppelin/token/ERC1155/ERC1155.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";
import {IERC1155MetadataURI} from "openzeppelin/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {Errors} from "src/utils/Errors.sol";

contract ScrapLyraVaultShareERC1155 is Errors, AccessControl, ERC1155Supply {
    bytes32 public constant DEV_ROLE = keccak256("DEV_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    constructor(address dev, address vault) ERC1155("") {
        if (dev == address(0)) revert Zero();
        if (vault == address(0)) revert Zero();

        // Grant the dev role which enables limited access to permissioned methods
        _setupRole(DEV_ROLE, dev);

        // Grant the vault role which enables minting and burning of share tokens
        _setupRole(VAULT_ROLE, vault);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, ERC1155) returns (bool) {
        return
            interfaceId == type(IAccessControl).interfaceId ||
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function setURI(string memory newuri) external onlyRole(DEV_ROLE) {
        _setURI(newuri);
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyRole(VAULT_ROLE) {
        _mint(account, id, amount, data);
    }

    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external onlyRole(VAULT_ROLE) {
        _burn(from, id, amount);
    }
}
