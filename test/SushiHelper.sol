// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

interface IUniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IUniswapV2Pair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

interface IUSDC {
    function gatewayAddress() external view returns (address);

    function bridgeMint(address to, uint256 amount) external;
}

interface IWETH {
    function depositTo(address to) external payable;
}

interface MiniChefV2 {
    function deposit(uint256 pid, uint256 amount, address to) external;
}

contract SushiHelper is Test {
    using SafeTransferLib for ERC20;

    IWETH internal constant WETH =
        IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IUSDC internal constant USDC =
        IUSDC(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    function _mintUsdc(address to, uint256 amount) internal {
        ERC20 usdc = ERC20(address(USDC));
        uint256 preMintBalance = usdc.balanceOf(to);

        vm.startPrank(USDC.gatewayAddress());

        USDC.bridgeMint(to, amount);

        vm.stopPrank();

        assertEq(preMintBalance + amount, usdc.balanceOf(to));
    }

    function _mintWeth(address to, uint256 amount) internal {
        ERC20 weth = ERC20(address(WETH));
        uint256 preMintBalance = weth.balanceOf(to);

        vm.deal(address(this), amount);

        WETH.depositTo(to);

        assertEq(preMintBalance + amount, weth.balanceOf(to));
    }

    function _getQuote(
        IUniswapV2Pair pair,
        uint256 amount,
        bool zeroForOne
    ) internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        return
            zeroForOne
                ? ((amount * reserve1) / reserve0)
                : ((amount * reserve0) / reserve1);
    }

    function _addLiquidityETH(
        IUniswapV2Router02 router,
        IUniswapV2Pair pair,
        ERC20 token,
        uint256 amount
    )
        internal
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        address token0 = pair.token0();
        bool zeroForOne = address(token) == address(token0);
        uint256 ethAmount = _getQuote(pair, amount, zeroForOne);

        token.safeApprove(address(router), amount);

        return
            router.addLiquidityETH{value: ethAmount}(
                address(token),
                amount,
                amount,
                ethAmount,
                address(this),
                block.timestamp + 20 minutes
            );
    }

    function _stakeLiquidity(
        ERC20 lpToken,
        MiniChefV2 chef,
        uint256 pid,
        uint256 amount
    ) internal {
        lpToken.safeApprove(address(chef), amount);

        chef.deposit(pid, amount, address(this));
    }
}
