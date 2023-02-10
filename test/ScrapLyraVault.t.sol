// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Helper} from "test/Helper.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {ILiquidityToken} from "src/interfaces/ILiquidityToken.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {ScrapLyraVault} from "src/ScrapLyraVault.sol";
import {ScrapLyraVaultShareERC1155} from "src/ScrapLyraVaultShareERC1155.sol";
import {ConvertDecimals} from "src/libraries/ConvertDecimals.sol";
import {DecimalMath} from "src/libraries/DecimalMath.sol";

interface IOptionMarket {
    function getNumLiveBoards() external view returns (uint256);
}

contract ScrapLyraVaultTest is Helper, ERC1155TokenReceiver {
    ILiquidityToken private constant LYRA_USDC_LIQUIDITY_TOKEN =
        ILiquidityToken(0xBdF4E630ded14a129aE302f930D1Ae1B40fd02aa);
    ILiquidityPool private constant LYRA_USDC_LIQUIDITY_POOL =
        ILiquidityPool(0xB619913921356904Bf62abA7271E694FD95AA10D);
    IOptionMarket private constant OPTION_MARKET =
        IOptionMarket(0x919E5e0C096002cb8a21397D724C4e3EbE77bC15);

    bytes private constant UNAUTHORIZED_ERROR = bytes("UNAUTHORIZED");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    ScrapLyraVault private immutable vault =
        new ScrapLyraVault(
            LYRA_USDC_LIQUIDITY_TOKEN,
            "Scrap x Lyra | ETH Vault",
            "scrapLYRA-ETH",
            18
        );
    ScrapLyraVaultShareERC1155 private immutable depositShare;
    ScrapLyraVaultShareERC1155 private immutable withdrawShare;
    uint256 private immutable testAccLen;

    address[] private testAcc = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
    ];

    event Deposit(
        address indexed msgSender,
        address indexed receiver,
        uint256 amount,
        uint256 indexed queuedDepositId,
        uint256 shareAmount
    );

    constructor() {
        depositShare = vault.depositShare();
        withdrawShare = vault.withdrawShare();
        testAccLen = testAcc.length;
    }

    /*//////////////////////////////////////////////////////////////
                            deposit TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotDepositReceiverZero() external {
        address receiver = address(0);
        uint256 amount = 1e18;

        vm.expectRevert(Zero.selector);

        vault.deposit(receiver, amount);
    }

    function testCannotDepositAmountZero() external {
        address receiver = address(this);
        uint256 amount = 0;

        vm.expectRevert(Zero.selector);

        vault.deposit(receiver, amount);
    }

    function testDeposit() external {
        address receiver = address(this);
        uint256 amount = 1e6;

        _mintUsdc(address(this), amount);

        USDC.approve(address(vault), amount);

        uint256 shareAmount = amount;
        uint256 queuedDepositId = LYRA_USDC_LIQUIDITY_POOL
            .nextQueuedDepositId();

        if (OPTION_MARKET.getNumLiveBoards() == 0) {
            shareAmount = DecimalMath.divideDecimal(
                ConvertDecimals.convertTo18(amount, USDC.decimals()),
                LYRA_USDC_LIQUIDITY_POOL.getTokenPrice()
            );
            queuedDepositId = 0;
        }

        vm.expectEmit(true, true, true, true, address(vault));

        emit Deposit(
            address(this),
            receiver,
            amount,
            queuedDepositId,
            shareAmount
        );

        vault.deposit(receiver, amount);

        if (OPTION_MARKET.getNumLiveBoards() == 0) {
            assertEq(shareAmount, vault.balanceOf(receiver));
            assertEq(shareAmount, vault.totalSupply());
        } else {
            assertEq(amount, depositShare.balanceOf(receiver, queuedDepositId));
            assertEq(amount, depositShare.totalSupply(queuedDepositId));
        }
    }

    function testDepositFuzz(
        uint40 amountModifier,
        bool receiverCaller
    ) external {
        vm.assume(amountModifier != 0);

        for (uint256 i; i < testAccLen; ) {
            address receiver = testAcc[i];
            uint256 amount = 1e6 + (amountModifier * i);
            address caller = receiverCaller ? receiver : address(this);

            _mintUsdc(caller, amount);

            vm.startPrank(caller);

            USDC.approve(address(vault), amount);

            uint256 shareAmount = amount;
            uint256 queuedDepositId = LYRA_USDC_LIQUIDITY_POOL
                .nextQueuedDepositId();

            if (OPTION_MARKET.getNumLiveBoards() == 0) {
                shareAmount = DecimalMath.divideDecimal(
                    ConvertDecimals.convertTo18(amount, USDC.decimals()),
                    LYRA_USDC_LIQUIDITY_POOL.getTokenPrice()
                );
                queuedDepositId = 0;
            }

            vm.expectEmit(true, true, true, true, address(vault));

            emit Deposit(
                caller,
                receiver,
                amount,
                queuedDepositId,
                shareAmount
            );

            vault.deposit(receiver, amount);

            vm.stopPrank();

            if (OPTION_MARKET.getNumLiveBoards() == 0) {
                assertEq(shareAmount, vault.balanceOf(receiver));
                assertEq(shareAmount, vault.totalSupply());
            } else {
                assertEq(
                    amount,
                    depositShare.balanceOf(receiver, queuedDepositId)
                );
                assertEq(amount, depositShare.totalSupply(queuedDepositId));
            }

            unchecked {
                ++i;
            }
        }
    }
}
