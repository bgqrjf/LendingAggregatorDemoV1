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
        address _distributeFrom
    ) internal virtual {
        // update index value based on total amount and new rewards gained since last update
        uint256 currentIndex = _updateCurrentIndex(
            _asset,
            _type,
            _totalAmount,
            _getNewRewards(_asset, _type, _distributeFrom)
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
        address _distributeFrom
    ) internal virtual {
        // update index value based on total amount and new rewards gained since last update
        uint256 currentIndex = _updateCurrentIndex(
            _asset,
            _type,
            _totalAmount,
            _getNewRewards(_asset, _type, _distributeFrom)
        );

        // collect rewards earned since last checkpoint
        uint256 rewardsToCollect = _collectRewards(
            _rewardTokens(_asset, _type),
            _getUserRewards(_asset, _type, _account, _amount, currentIndex)
        );

        // transfer reward token
        _rewardTokens(_asset, _type).safeTransfer(
            _account,
            rewardsToCollect,
            0
        );
    }

    // Returns new rewards token address (must be overridden in child contract)
    function _rewardTokens(
        address,
        uint8
    ) internal view virtual returns (address) {
        return address(0);
    }

    // Returns new rewards gained since last update (must be overridden in child contract)
    function _getNewRewards(
        address,
        uint8,
        address
    ) internal view virtual returns (uint256) {
        return 0;
    }

    // Collects rewards (must be overridden in child contract)
    function _collectRewards(
        address,
        uint256 _newAmount
    ) internal virtual returns (uint256) {
        return _newAmount;
    }

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

    // Returns total rewards for an asset and type (must be overridden in child contract)
    function _getTotalRewards(
        address,
        uint8,
        address
    ) internal view virtual returns (uint256) {
        return 0;
    }

    // Returns new index value based on total amount and new rewards gained since last update
    function _getCurrentIndex(
        address _asset,
        uint8 _type,
        uint256 _totalAmount,
        uint256 _newRewards
    ) internal view returns (uint256) {
        return
            _totalAmount > 0
                ? currentIndexes[_asset][_type] +
                    (_newRewards * Utils.QUINTILLION) /
                    _totalAmount
                : 0;
    }

    // Updates index value based on total amount and new rewards gained since last update
    function _updateCurrentIndex(
        address _asset,
        uint8 _type,
        uint256 _totalAmount,
        uint256 _newRewards
    ) private returns (uint256 currentIndex) {
        currentIndex = _getCurrentIndex(
            _asset,
            _type,
            _totalAmount,
            _newRewards
        );
        currentIndexes[_asset][_type] = currentIndex;
    }
}
