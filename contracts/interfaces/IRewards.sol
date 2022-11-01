// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";
import "./IRouter.sol";

interface IRewards {
    function startMiningSupplyReward(
        address asset,
        address account,
        uint256 amount,
        uint256 _totalShare
    ) external;

    function stopMiningSupplyReward(
        address asset,
        address account,
        uint256 amount,
        uint256 _totalShare
    ) external;

    function startMiningBorrowReward(
        address asset,
        address account,
        uint256 amount,
        uint256 _totalShare
    ) external;

    function stopMiningBorrowReward(
        address asset,
        address account,
        uint256 amount,
        uint256 _totalShare
    ) external;

    function claim(
        address _asset,
        address _account,
        uint256 _totalShare
    ) external returns (uint256[] memory rewardsToCollect);

    function addProtocol(IProtocol _protocol) external;
}
