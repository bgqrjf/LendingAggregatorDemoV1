// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./libraries/internals/Utils.sol";
import "./libraries/internals/TransferHelper.sol";

contract RewardsDistribution {
    using TransferHelper for address;

    mapping(address => mapping(uint8 => mapping(address => uint256)))
        public userIndexes; // stores user stakes for each asset and type
    mapping(address => mapping(uint8 => uint256)) public currentIndexes; // stores index value for each asset and type

    // Deposit tokens to start staking
    function _newStake(
        address _asset,
        uint8 _type,
        address _account,
        uint256 _userBalance,
        uint256 _newAmount,
        uint256 _totalAmount,
        uint256 _newRewards
    ) internal virtual {
        // update index value based on total amount and new rewards gained since last update
        uint256 currentIndex = _updateCurrentIndex(
            _asset,
            _type,
            _totalAmount,
            _newRewards
        );

        // weighted average formula
        userIndexes[_asset][_type][_account] =
            (userIndexes[_asset][_type][_account] *
                _userBalance +
                currentIndex *
                _newAmount) /
            (_userBalance + _newAmount);
    }

    // Withdraw tokens and claim rewards
    function _newUnstake(
        address _asset,
        address _account,
        uint8 _type,
        uint256 _amount,
        uint256 _totalAmount,
        uint256 _newRewards
    ) internal virtual returns (uint256 rewardsToCollect) {
        // update index value based on total amount and new rewards gained since last update
        uint256 currentIndex = _updateCurrentIndex(
            _asset,
            _type,
            _totalAmount,
            _newRewards
        );

        // collect rewards earned since last checkpoint
        rewardsToCollect = _getUserRewards(
            _asset,
            _type,
            _account,
            _amount,
            currentIndex
        );
    }

    // Returns new rewards token address (must be overridden in child contract)
    function _rewardTokens(
        address,
        uint8
    ) internal view virtual returns (address) {}

    // Returns new rewards gained since last update (must be overridden in child contract)
    function _claimNewRewards(
        address,
        uint8
    ) internal virtual returns (uint256 newRewards) {}

    // View the total rewards earned by a user
    function _getUserRewards(
        address _asset,
        uint8 _type,
        address _account,
        uint256 _amount,
        uint256 _currentIndex
    ) internal view virtual returns (uint256) {
        uint256 userIndex = userIndexes[_asset][_type][_account];
        // calculate rewards earned since last checkpoint based on difference in index values and current stake amount
        return ((_currentIndex - userIndex) * _amount) / Utils.QUINTILLION;
    }

    // Returns new index value based on total amount and new rewards gained since last update
    function _getCurrentIndex(
        address _asset,
        uint8 _type,
        uint256 _totalAmount,
        uint256 _newRewards
    ) internal view returns (uint256) {
        return
            _newRewards > 0
                ? currentIndexes[_asset][_type] +
                    (_newRewards * Utils.QUINTILLION) /
                    _totalAmount
                : currentIndexes[_asset][_type];
    }

    // Updates index value based on total amount and new rewards gained since last update
    function _updateCurrentIndex(
        address _asset,
        uint8 _type,
        uint256 _totalAmount,
        uint256 _newRewards
    ) internal returns (uint256 currentIndex) {
        currentIndex = _getCurrentIndex(
            _asset,
            _type,
            _totalAmount,
            _newRewards
        );
        currentIndexes[_asset][_type] = currentIndex;
    }
}
