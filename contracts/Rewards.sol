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
    mapping(address => mapping(uint8 => mapping(address => uint256)))
        public uncollectedRewards;

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
        uint8 rewardType = uint8(
            _isBorrow ? RewardType.CompoundBorrow : RewardType.CompoundSupply
        );

        uint256 totalRewards = _getTotalRewards(
            _asset,
            rewardType,
            protocolsHandler
        );

        uint256 newRewards = totalRewards - reserves[_asset][rewardType];
        reserves[_asset][rewardType] = totalRewards;

        if (_userBalanceAfter > _userBalanceBefore) {
            _newStake(
                _asset,
                rewardType,
                _account,
                _userBalanceAfter,
                _userBalanceAfter - _userBalanceBefore,
                _totalAmountBefore,
                newRewards
            );
        } else {
            uncollectedRewards[_asset][rewardType][_account] += _newUnstake(
                _asset,
                _account,
                rewardType,
                _userBalanceBefore - _userBalanceAfter,
                _totalAmountBefore,
                newRewards
            );
        }
    }

    //  rewards are expected to be transfered out to _account afterwards
    function claimRewards(
        address _asset,
        bool _isBorrow,
        address _account,
        uint256 _userBalance,
        uint256 _totalAmount
    ) external override onlyRole(REWARD_ADMIN) returns (uint256 userRewards) {
        uint8 rewardType = uint8(
            _isBorrow ? RewardType.CompoundBorrow : RewardType.CompoundSupply
        );

        uint256 uncollectedReward = uncollectedRewards[_asset][rewardType][
            _account
        ];

        if (_userBalance + uncollectedReward == 0) {
            return 0;
        }

        uint256 currentIndex = _updateCurrentIndex(
            _asset,
            rewardType,
            _totalAmount,
            _getTotalRewards(_asset, rewardType, protocolsHandler) -
                reserves[_asset][rewardType]
        );

        uint256 newUserRewards = _getUserRewards(
            _asset,
            rewardType,
            _account,
            _userBalance,
            currentIndex
        );

        userRewards = uncollectedReward + newUserRewards;

        userIndexes[_asset][rewardType][_account] = currentIndex;
        delete uncollectedRewards[_asset][rewardType][_account];
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

    function rewardsToken(
        address _asset,
        uint8 _type
    ) external view override returns (address) {
        return _rewardTokens(_asset, _type);
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
