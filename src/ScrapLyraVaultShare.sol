// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {Errors} from "src/utils/Errors.sol";
import {IFlywheelRewards} from "src/interfaces/IFlywheelRewards.sol";

contract ScrapLyraVaultShare is Errors, ReentrancyGuard, AccessControl, ERC20 {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    struct RewardsState {
        uint224 index;
        uint32 lastUpdatedTimestamp;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    uint224 public constant ONE = 1e18;

    ERC20 public immutable rewardToken;

    IFlywheelRewards public flywheelRewards;

    RewardsState public strategyState;
    mapping(address => uint224) public userIndex;
    mapping(address => uint256) public rewardsAccrued;

    event AccrueRewards(
        address indexed user,
        uint256 rewardsDelta,
        uint256 rewardsIndex
    );
    event ClaimRewards(address indexed user, uint256 amount);
    event FlywheelRewardsUpdate(address indexed newFlywheelRewards);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        ERC20 _rewardToken,
        IFlywheelRewards _flywheelRewards,
        address admin,
        address vault
    ) ERC20(_name, _symbol, _decimals) {
        if (address(_rewardToken) == address(0)) revert Zero();
        if (address(_flywheelRewards) == address(0)) revert Zero();
        if (admin == address(0)) revert Zero();
        if (vault == address(0)) revert Zero();

        rewardToken = _rewardToken;
        flywheelRewards = _flywheelRewards;

        _setupRole(ADMIN_ROLE, admin);
        _setupRole(VAULT_ROLE, vault);
    }

    function setFlywheelRewards(
        IFlywheelRewards newFlywheelRewards
    ) external onlyRole(ADMIN_ROLE) {
        if (address(newFlywheelRewards) == address(0)) revert Zero();

        uint256 oldRewardBalance = rewardToken.balanceOf(
            address(flywheelRewards)
        );

        if (oldRewardBalance > 0) {
            rewardToken.safeTransferFrom(
                address(flywheelRewards),
                address(newFlywheelRewards),
                oldRewardBalance
            );
        }

        flywheelRewards = newFlywheelRewards;

        emit FlywheelRewardsUpdate(address(newFlywheelRewards));
    }

    function _accrueStrategy(
        RewardsState memory state
    ) private returns (RewardsState memory rewardsState) {
        uint256 strategyRewardsAccrued = flywheelRewards.getAccruedRewards(
            this,
            state.lastUpdatedTimestamp
        );

        rewardsState = state;

        if (strategyRewardsAccrued > 0) {
            uint256 supplyTokens = totalSupply;
            uint224 deltaIndex;

            if (supplyTokens != 0)
                deltaIndex = ((strategyRewardsAccrued * ONE) / supplyTokens)
                    .safeCastTo224();

            rewardsState = RewardsState({
                index: state.index + deltaIndex,
                lastUpdatedTimestamp: block.timestamp.safeCastTo32()
            });
            strategyState = rewardsState;
        }
    }

    function _accrueUser(
        address user,
        RewardsState memory state
    ) private returns (uint256) {
        uint224 strategyIndex = state.index;
        uint224 supplierIndex = userIndex[user];
        userIndex[user] = strategyIndex;

        if (supplierIndex == 0) supplierIndex = ONE;

        uint224 deltaIndex = strategyIndex - supplierIndex;
        uint256 supplierTokens = balanceOf[user];
        uint256 supplierDelta = (supplierTokens * deltaIndex) / ONE;
        uint256 supplierAccrued = rewardsAccrued[user] + supplierDelta;
        rewardsAccrued[user] = supplierAccrued;

        emit AccrueRewards(user, supplierDelta, strategyIndex);

        return supplierAccrued;
    }

    function _accrue(address user) private returns (uint256) {
        RewardsState memory state = strategyState;

        if (state.index == 0) return 0;

        state = _accrueStrategy(state);

        return _accrueUser(user, state);
    }

    function _accrue(
        address user,
        address secondUser
    ) private returns (uint256, uint256) {
        RewardsState memory state = strategyState;

        if (state.index == 0) return (0, 0);

        state = _accrueStrategy(state);

        return (_accrueUser(user, state), _accrueUser(secondUser, state));
    }

    function claimRewards(address user) external nonReentrant {
        if (user == address(0)) revert Zero();

        uint256 accrued = rewardsAccrued[user];

        if (accrued != 0) {
            rewardsAccrued[user] = 0;

            rewardToken.safeTransferFrom(
                address(flywheelRewards),
                user,
                accrued
            );

            emit ClaimRewards(user, accrued);
        }
    }

    function mint(address _to, uint256 _amount) external onlyRole(VAULT_ROLE) {
        _accrue(_to);

        _mint(_to, _amount);
    }

    function burn(
        address _from,
        uint256 _amount
    ) external onlyRole(VAULT_ROLE) {
        _accrue(_from);

        _burn(_from, _amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        if (to == address(0)) revert Zero();
        if (amount == 0) revert Zero();

        _accrue(msg.sender, to);

        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override nonReentrant returns (bool) {
        if (from == address(0)) revert Zero();
        if (to == address(0)) revert Zero();
        if (amount == 0) revert Zero();

        _accrue(from, to);

        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
}
