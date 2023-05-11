// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ImmutableCreate2Factory} from "src/deployment/ImmutableCreate2Factory.sol";
import {TransientContract} from "src/deployment/TransientContract.sol";
import {ScrapWrappedStakedLyra} from "src/ScrapWrappedStakedLyra.sol";
import {ICurveFactory} from "src/interfaces/ICurveFactory.sol";

contract MainnetVaultScript is Script {
    using SafeTransferLib for ERC20;

    ICurveFactory private constant CURVE_FACTORY =
        ICurveFactory(0xF18056Bbd320E96A48e3Fbf8bC061322531aac99);
    ERC20 private constant LYRA =
        ERC20(0x01BA67AAC7f75f647D94220Cc98FB30FCc5105Bf);

    function _getSalt(
        address caller,
        string memory word
    ) private pure returns (bytes32) {
        return bytes32(abi.encodePacked(bytes20(caller), bytes12(bytes(word))));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        bytes32 factorySalt = _getSalt(
            vm.envAddress("DEPLOYER"),
            vm.envString("FACTORY_SALT")
        );
        address factoryOwner = vm.envAddress("DEPLOYER");

        // Deploy factory from EOA using the specified salt
        ImmutableCreate2Factory factory = new ImmutableCreate2Factory{
            salt: factorySalt
        }(factoryOwner);

        address vaultOwner = vm.envAddress("OWNER");
        address vaultLiquidityProvider = vm.envAddress("OWNER");
        bytes memory vaultInitCode = abi.encodePacked(
            type(ScrapWrappedStakedLyra).creationCode,
            abi.encode(vaultOwner, vaultLiquidityProvider)
        );

        // Set the initCode, which will be used by the transient contract
        factory.setInitializationCode(vaultInitCode);

        bytes32 vaultSalt = factory.getSalt(
            vm.envAddress("DEPLOYER"),
            vm.envString("VAULT_SALT")
        );

        // Get the vault address
        address vaultAddr = factory.getTransientChild(
            // Deploy the transient contract using the specified salt
            factory.safeCreate2(vaultSalt, type(TransientContract).creationCode)
        );

        console.log(address(factory));
        console.log(vaultAddr);

        vm.stopBroadcast();
    }
}
