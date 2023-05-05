// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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

    function claimRewards(
        address _asset,
        bool _isBorrow,
        address _account,
        uint256 _userBalance,
        uint256 _totalAmount
    ) external returns (uint256 userRewards);

    function rewardsToken(
        address _asset,
        uint8 _type
    ) external view returns (address);

    function addRewardAdmin(address _newAdmin) external;

    function addProtocol(IProtocol _protocol) external;
}
