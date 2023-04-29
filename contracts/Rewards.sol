// SP// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IRewards.sol";
import "./RewardsDistribution.sol";

contract Rewards is
    IRewards,
    RewardsDistribution,
    AccessControlUpgradeable,
    OwnableUpgradeable
{
    using TransferHelper for address;

    IProtocol[] public protocols;
    address public protocolsHandler;
    mapping(address => mapping(uint8 => uint256)) public reserves;

    bytes32 public constant REWARD_ADMIN =
        keccak256(abi.encode("reward admin"));

    enum RewardType {
        CompoundSupply,
        CompoundBorrow
    }

    function initialize(address _protocolsHandler) external initializer {
        __Ownable_init();
        __AccessControl_init();
        protocolsHandler = _protocolsHandler;
    }

    function updateRewardShare(
        address _asset,
        bool _isBorrow,
        address _account,
        uint256 _userBalanceBefore,
        uint256 _userBalanceAfter,
        uint256 _totalAmountBefore
    ) external override onlyRole(REWARD_ADMIN) {
        uint8 rewardType = _isBorrow
            ? uint8(RewardType.CompoundBorrow)
            : uint8(RewardType.CompoundSupply);

        uint256 totalRewards = _getTotalRewards(
            _asset,
            rewardType,
            protocolsHandler
        );

        uint256 newRewards = totalRewards - reserves[_asset][rewardType];
        reserves[_asset][rewardType] = totalRewards;

        _userBalanceAfter > _userBalanceBefore
            ? _newStake(
                _asset,
                rewardType,
                _account,
                _userBalanceAfter,
                _userBalanceAfter - _userBalanceBefore,
                _totalAmountBefore,
                newRewards
            )
            : _newUnstake(
                _asset,
                _account,
                rewardType,
                _userBalanceBefore - _userBalanceAfter,
                _totalAmountBefore,
                newRewards
            );
    }

    function getUserRewards(
        address _asset,
        bool _isBorrow,
        address _account,
        uint256 _amount,
        uint256 _totalAmount
    ) external view override returns (uint256) {
        uint8 rewardType = uint8(
            _isBorrow ? RewardType.CompoundBorrow : RewardType.CompoundSupply
        );

        uint256 currentIndex = _getCurrentIndex(
            _asset,
            rewardType,
            _totalAmount,
            _getNewRewards(_asset, rewardType, protocolsHandler)
        );

        return
            _getUserRewards(
                _asset,
                rewardType,
                _account,
                _amount,
                currentIndex
            );
    }

    function addRewardAdmin(address _newAdmin) external override onlyOwner {
        _grantRole(REWARD_ADMIN, _newAdmin);
    }

    function addProtocol(IProtocol _protocol) external override onlyOwner {
        protocols.push(_protocol);
    }

    function _rewardTokens(
        address,
        uint8
    ) internal view override returns (address) {
        return protocols[1].rewardToken();
    }

    function _getNewRewards(
        address _asset,
        uint8 _type,
        address _account
    ) internal view override returns (uint256 amount) {
        amount =
            _getTotalRewards(_asset, _type, _account) -
            reserves[_asset][_type];
    }

    function _collectRewards(
        address _asset,
        uint256 _newAmount
    ) internal override returns (uint256) {
        if (_asset.balanceOf(protocolsHandler) < _newAmount) {
            protocols[1].claimRewards(protocolsHandler);
        }
        return _newAmount;
    }

    function _getTotalRewards(
        address _asset,
        uint8 _type,
        address _account
    ) internal view override returns (uint256) {
        return
            protocols[1].totalRewards(
                _asset,
                _account,
                _type == uint8(RewardType.CompoundSupply)
            );
    }
}
