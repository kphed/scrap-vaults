// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Helper} from "test/Helper.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ILiquidityToken} from "src/interfaces/ILiquidityToken.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {ScrapLyraVault} from "src/ScrapLyraVault.sol";
import {ScrapLyraVaultShareERC1155} from "src/ScrapLyraVaultShareERC1155.sol";
import {ConvertDecimals} from "src/libraries/ConvertDecimals.sol";
import {DecimalMath} from "src/libraries/DecimalMath.sol";
import {IGMXAdapter} from "test/interfaces/IGMXAdapter.sol";

interface IOptionMarket {
    function getNumLiveBoards() external view returns (uint256);

    function getLiveBoards() external view returns (uint256[] memory);
}

interface IGreekCache {
    function isGlobalCacheStale(uint256) external view returns (bool);

    function updateBoardCachedGreeks(uint256) external;
}

contract ScrapLyraVaultTest is Helper, ERC1155TokenReceiver {
    using FixedPointMathLib for uint256;

    ILiquidityToken private constant USDC_LIQUIDITY_TOKEN =
        ILiquidityToken(0xBdF4E630ded14a129aE302f930D1Ae1B40fd02aa);
    ILiquidityPool private constant USDC_LIQUIDITY_POOL =
        ILiquidityPool(0xB619913921356904Bf62abA7271E694FD95AA10D);
    address private constant OPTION_MARKET_ADDR =
        0x919E5e0C096002cb8a21397D724C4e3EbE77bC15;
    IOptionMarket private constant OPTION_MARKET =
        IOptionMarket(OPTION_MARKET_ADDR);
    IGMXAdapter private constant GMX_ADAPTER =
        IGMXAdapter(0x7D135662818d3540bd6f23294bFDB6946c52C9AB);

    IGreekCache private constant GREEK_CACHE =
        IGreekCache(0x4b236Ac3B8d4666CbdC4E725C4366382AA30d86b);

    bytes private constant UNAUTHORIZED_ERROR = bytes("UNAUTHORIZED");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    ScrapLyraVault private immutable vault =
        new ScrapLyraVault(
            address(this),
            USDC_LIQUIDITY_TOKEN,
            "Scrap x Lyra | ETH Vault",
            "scrapLYRA-ETH",
            18
        );
    ScrapLyraVaultShareERC1155 private immutable depositShare;
    ScrapLyraVaultShareERC1155 private immutable withdrawShare;
    address private immutable vaultAddr;
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
    event ConvertDepositShares(
        address indexed msgSender,
        address indexed receiver,
        uint256 indexed id,
        uint256 amount,
        uint256 vaultShareAmount
    );

    constructor() {
        depositShare = vault.depositShare();
        withdrawShare = vault.withdrawShare();
        vaultAddr = address(vault);
        testAccLen = testAcc.length;
    }

    function _processDepositQueue() private {
        uint256 nextQueuedDepositId = USDC_LIQUIDITY_POOL.nextQueuedDepositId();

        ILiquidityPool.LiquidityPoolParameters
            memory lpParams = USDC_LIQUIDITY_POOL.getLpParams();
        ILiquidityPool.QueuedDeposit memory queuedDeposit = USDC_LIQUIDITY_POOL
            .queuedDeposits(nextQueuedDepositId - 1);

        vm.warp(queuedDeposit.depositInitiatedTime + lpParams.depositDelay + 1);

        IGMXAdapter.MarketPricingParams memory marketPricingParams = GMX_ADAPTER
            .marketPricingParams(OPTION_MARKET_ADDR);
        marketPricingParams.chainlinkStalenessCheck = 10 days;

        vm.startPrank(GMX_ADAPTER.owner());

        GMX_ADAPTER.setMarketPricingParams(
            OPTION_MARKET_ADDR,
            marketPricingParams
        );

        vm.stopPrank();

        uint256[] memory liveBoards = OPTION_MARKET.getLiveBoards();

        for (uint256 i; i < liveBoards.length; ++i) {
            GREEK_CACHE.updateBoardCachedGreeks(liveBoards[i]);
        }

        USDC_LIQUIDITY_POOL.processDepositQueue(
            nextQueuedDepositId - USDC_LIQUIDITY_POOL.queuedDepositHead()
        );
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

        USDC.approve(vaultAddr, amount);

        uint256 shareAmount = amount;
        uint256 queuedDepositId = USDC_LIQUIDITY_POOL.nextQueuedDepositId();

        if (OPTION_MARKET.getNumLiveBoards() == 0) {
            shareAmount = DecimalMath.divideDecimal(
                ConvertDecimals.convertTo18(amount, USDC.decimals()),
                USDC_LIQUIDITY_POOL.getTokenPrice()
            );
            queuedDepositId = 0;
        }

        vm.expectEmit(true, true, true, true, vaultAddr);

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
        for (uint256 i; i < testAccLen; ) {
            address receiver = testAcc[i];
            uint256 amount = 1e6 + (amountModifier * i);
            address caller = receiverCaller ? receiver : address(this);

            _mintUsdc(caller, amount);

            vm.startPrank(caller);

            USDC.approve(vaultAddr, amount);

            uint256 shareAmount = amount;
            uint256 queuedDepositId = USDC_LIQUIDITY_POOL.nextQueuedDepositId();

            if (OPTION_MARKET.getNumLiveBoards() == 0) {
                shareAmount = DecimalMath.divideDecimal(
                    ConvertDecimals.convertTo18(amount, USDC.decimals()),
                    USDC_LIQUIDITY_POOL.getTokenPrice()
                );
                queuedDepositId = 0;
            }

            vm.expectEmit(true, true, true, true, vaultAddr);

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

    /*//////////////////////////////////////////////////////////////
                        convertDepositShares TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotConvertDepositSharesReceiverZero() external {
        address receiver = address(0);
        uint256 id = 1;
        uint256 amount = 1;

        vm.expectRevert(Zero.selector);

        vault.convertDepositShares(receiver, id, amount);
    }

    function testCannotConvertDepositSharesIdZero() external {
        address receiver = address(this);
        uint256 id = 0;
        uint256 amount = 1;

        vm.expectRevert(Zero.selector);

        vault.convertDepositShares(receiver, id, amount);
    }

    function testCannotConvertDepositSharesAmountZero() external {
        address receiver = address(this);
        uint256 id = 1;
        uint256 amount = 0;

        vm.expectRevert(Zero.selector);

        vault.convertDepositShares(receiver, id, amount);
    }

    function testConvertDepositShares() external {
        address receiver = address(this);
        uint256 amount = 1e6;
        uint256 id = USDC_LIQUIDITY_POOL.nextQueuedDepositId();

        _mintUsdc(address(this), amount);

        USDC.approve(vaultAddr, amount);

        vault.deposit(receiver, amount);

        _processDepositQueue();

        ILiquidityPool.QueuedDeposit memory queuedDeposit = USDC_LIQUIDITY_POOL
            .queuedDeposits(id);

        depositShare.setApprovalForAll(vaultAddr, true);

        vm.expectEmit(true, true, true, true, vaultAddr);

        emit ConvertDepositShares(
            address(this),
            receiver,
            id,
            amount,
            queuedDeposit.mintedTokens
        );

        vault.convertDepositShares(receiver, id, amount);

        assertEq(0, depositShare.balanceOf(receiver, id));
        assertEq(queuedDeposit.mintedTokens, vault.balanceOf(receiver));
    }

    function testConvertDepositSharesFuzz(uint40 amountModifier) external {
        uint256 amount = 1e6 + uint256(amountModifier);
        uint256 id = USDC_LIQUIDITY_POOL.nextQueuedDepositId();

        _mintUsdc(address(this), amount);

        USDC.approve(vaultAddr, amount);

        vault.deposit(address(this), amount);

        _processDepositQueue();

        uint256 mintedTokens = USDC_LIQUIDITY_POOL
            .queuedDeposits(id)
            .mintedTokens;

        assertEq(mintedTokens, USDC_LIQUIDITY_TOKEN.balanceOf(vaultAddr));

        for (uint256 i; i < testAccLen; ) {
            address receiver = testAcc[i];

            // Transfer a portion to the receiver to verify conversion math
            uint256 conversionAmount = (depositShare.balanceOf(
                address(this),
                id
            ) - 1_000).mulDivDown(i + 1, testAccLen);

            depositShare.safeTransferFrom(
                address(this),
                receiver,
                id,
                conversionAmount,
                ""
            );

            uint256 vaultShares = (mintedTokens - vault.sharesMinted(id))
                .mulDivDown(conversionAmount, depositShare.totalSupply(id));

            vm.startPrank(receiver);

            depositShare.setApprovalForAll(vaultAddr, true);

            vm.expectEmit(true, true, true, true, vaultAddr);

            emit ConvertDepositShares(
                receiver,
                receiver,
                id,
                conversionAmount,
                vaultShares
            );

            vault.convertDepositShares(receiver, id, conversionAmount);

            vm.stopPrank();

            assertEq(0, depositShare.balanceOf(receiver, id));
            assertEq(vaultShares, vault.balanceOf(receiver));

            unchecked {
                ++i;
            }
        }

        uint256 remainingDepositShares = depositShare.balanceOf(
            address(this),
            id
        );
        uint256 remainingMintableShares = mintedTokens - vault.sharesMinted(id);

        depositShare.setApprovalForAll(vaultAddr, true);

        vm.expectEmit(true, true, true, true, vaultAddr);

        emit ConvertDepositShares(
            address(this),
            address(this),
            id,
            remainingDepositShares,
            remainingMintableShares
        );

        vault.convertDepositShares(address(this), id, remainingDepositShares);

        assertEq(0, depositShare.totalSupply(id));
        assertEq(mintedTokens, vault.sharesMinted(id));

        // Account for rounding down
        assertLe(
            mintedTokens.mulDivDown(remainingDepositShares, amount),
            vault.balanceOf(address(this))
        );
    }
}
