// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Owned} from "solmate/auth/Owned.sol";

/**
 * @title Immutable Create2 Contract Factory
 * @author 0age
 * @notice This contract provides a safeCreate2 function that takes a salt value
 * and a block of initialization code as arguments and passes them into inline
 * assembly. The contract prevents redeploys by maintaining a mapping of all
 * contracts that have already been deployed, and prevents frontrunning or other
 * collisions by requiring that the first 20 bytes of the salt are equal to the
 * address of the caller (this can be bypassed by setting the first 20 bytes to
 * the null address). There is also a view function that computes the address of
 * the contract that will be created when submitting a given salt or nonce along
 * with a given block of initialization code.
 * @dev CREATE2 will not be available on mainnet until (at least) block
 * 7,280,000. This contract has not yet been fully tested or audited - proceed
 * with caution and please share any exploits or optimizations you discover.
 */
contract ImmutableCreate2Factory is Owned {
    // mapping to track which addresses have already been deployed.
    mapping(address => bool) private _deployed;

    bytes private _initCode;

    constructor(address _owner) Owned(_owner) {}

    /**
     * @dev Modifier to ensure that the first 20 bytes of a submitted salt match
     * those of the calling account. This provides protection against the salt
     * being stolen by frontrunners or other attackers. The protection can also be
     * bypassed if desired by setting each of the first 20 bytes to zero.
     * @param salt bytes32 The salt value to check against the calling address.
     */
    modifier containsCaller(bytes32 salt) {
        // prevent contract submissions from being stolen from tx.pool by requiring
        // that the first 20 bytes of the submitted salt match msg.sender.
        require(
            (address(bytes20(salt)) == msg.sender) ||
                (bytes20(salt) == bytes20(0)),
            "Invalid salt - first 20 bytes of the salt must match calling address."
        );
        _;
    }

    function setInitializationCode(bytes memory code) external onlyOwner {
        _initCode = code;
    }

    function getInitializationCode() external view returns (bytes memory) {
        return _initCode;
    }

    /**
     * @dev Create a contract using CREATE2 by submitting a given salt or nonce
     * along with the initialization code for the contract. Note that the first 20
     * bytes of the salt must match those of the calling address, which prevents
     * contract creation events from being submitted by unintended parties.
     * @param salt bytes32 The nonce that will be passed into the CREATE2 call.
     * @param initializationCode bytes The initialization code that will be passed
     * into the CREATE2 call.
     * @return deploymentAddress Address of the contract that will be created, or the null address
     * if a contract already exists at that address.
     */
    function safeCreate2(
        bytes32 salt,
        bytes calldata initializationCode
    )
        external
        payable
        containsCaller(salt)
        returns (address deploymentAddress)
    {
        // move the initialization code from calldata to memory.
        bytes memory initCode = initializationCode;

        // determine the target address for contract deployment.
        address targetDeploymentAddress = address(
            uint160( // downcast to match the address type.
                uint256( // convert to uint to truncate upper digits.
                    keccak256( // compute the CREATE2 hash using 4 inputs.
                        abi.encodePacked( // pack all inputs to the hash together.
                            hex"ff", // start with 0xff to distinguish from RLP.
                            address(this), // this contract will be the caller.
                            salt, // pass in the supplied salt value.
                            keccak256(abi.encodePacked(initCode)) // pass in the hash of initialization code.
                        )
                    )
                )
            )
        );

        // ensure that a contract hasn't been previously deployed to target address.
        require(
            !_deployed[targetDeploymentAddress],
            "Invalid contract creation - contract has already been deployed."
        );

        // using inline assembly: load data and length of data, then call CREATE2.
        assembly {
            // solhint-disable-line
            let encoded_data := add(0x20, initCode) // load initialization code.
            let encoded_size := mload(initCode) // load the init code's length.
            deploymentAddress := create2(
                // call CREATE2 with 4 arguments.
                callvalue(), // forward any attached value.
                encoded_data, // pass in initialization code.
                encoded_size, // pass in init code's length.
                salt // pass in the salt value.
            )
        }

        // check address against target to ensure that deployment was successful.
        require(
            deploymentAddress == targetDeploymentAddress,
            "Failed to deploy contract using provided salt and initialization code."
        );

        // record the deployment of the contract to prevent redeploys.
        _deployed[deploymentAddress] = true;
    }

    /**
     * @dev Compute the address of the contract that will be created when
     * submitting a given salt or nonce to the contract along with the contract's
     * initialization code. The CREATE2 address is computed in accordance with
     * EIP-1014, and adheres to the formula therein of
     * `keccak256( 0xff ++ address ++ salt ++ keccak256(init_code)))[12:]` when
     * performing the computation. The computed address is then checked for any
     * existing contract code - if so, the null address will be returned instead.
     * @param salt bytes32 The nonce passed into the CREATE2 address calculation.
     * @param initCode bytes The contract initialization code to be used.
     * that will be passed into the CREATE2 address calculation.
     * @return deploymentAddress Address of the contract that will be created, or the null address
     * if a contract has already been deployed to that address.
     */
    function findCreate2Address(
        bytes32 salt,
        bytes calldata initCode
    ) external view returns (address deploymentAddress) {
        // determine the address where the contract will be deployed.
        deploymentAddress = address(
            uint160( // downcast to match the address type.
                uint256( // convert to uint to truncate upper digits.
                    keccak256( // compute the CREATE2 hash using 4 inputs.
                        abi.encodePacked( // pack all inputs to the hash together.
                            hex"ff", // start with 0xff to distinguish from RLP.
                            address(this), // this contract will be the caller.
                            salt, // pass in the supplied salt value.
                            keccak256(abi.encodePacked(initCode)) // pass in the hash of initialization code.
                        )
                    )
                )
            )
        );

        // return null address to signify failure if contract has been deployed.
        if (_deployed[deploymentAddress]) {
            return address(0);
        }
    }

    /**
     * @dev Internal view function for calculating a metamorphic contract address
     * that has been deployed via a transient contract given the address of the
     * transient contract.
     */
    function getTransientChild(
        address transientContractAddress
    ) external pure returns (address) {
        // determine the address of the metamorphic contract.
        return
            address(
                uint160( // downcast to match the address type.
                    uint256( // set to uint to truncate upper digits.
                        keccak256( // compute CREATE hash via RLP encoding.
                            abi.encodePacked( // pack all inputs to the hash together.
                                bytes1(0xd6), // first RLP byte.
                                bytes1(0x94), // second RLP byte.
                                transientContractAddress, // called by the transient contract.
                                bytes1(0x01) // nonce begins at 1 for contracts.
                            )
                        )
                    )
                )
            );
    }

    function getSalt(
        address caller,
        string memory word
    ) external pure returns (bytes32) {
        return bytes32(abi.encodePacked(bytes20(caller), bytes12(bytes(word))));
    }
}
