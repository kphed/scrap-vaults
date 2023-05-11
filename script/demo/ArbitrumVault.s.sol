// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {ImmutableCreate2Factory} from "src/deployment/ImmutableCreate2Factory.sol";
import {TransientContract} from "src/deployment/TransientContract.sol";
import {ScrapLyraVault} from "src/ScrapLyraVault.sol";
import {ILiquidityToken} from "src/interfaces/ILiquidityToken.sol";

contract ArbitrumVaultScript is Script {
    ILiquidityToken private constant USDC_LIQUIDITY_TOKEN =
        ILiquidityToken(0xBdF4E630ded14a129aE302f930D1Ae1B40fd02aa);

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
        bytes memory vaultInitCode = abi.encodePacked(
            type(ScrapLyraVault).creationCode,
            abi.encode(
                vaultOwner,
                USDC_LIQUIDITY_TOKEN,
                "ppmoon69",
                "PPMOON",
                69
            )
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
