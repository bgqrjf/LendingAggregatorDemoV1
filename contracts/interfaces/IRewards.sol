// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";
import "./IRouter.sol";

interface IRewards {
    function updateRewardShare(
        address _asset,
        bool _isBorrow,
        address _account,
        uint256 _userBalanceBefore,
        uint256 _userBalanceAfter,
        uint256 _totalAmountBefore
    ) external;

    function getUserRewards(
        address _asset,
        bool _isBorrow,
        address _account,
        uint256 _amount,
        uint256 _totalAmount
    ) external view returns (uint256);

    function addRewardAdmin(address _newAdmin) external;

    function addProtocol(IProtocol _protocol) external;
}
