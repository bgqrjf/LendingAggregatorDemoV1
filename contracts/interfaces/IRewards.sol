// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";
import "./IRouter.sol";

interface IRewards {
    function startMiningSupplyReward(
        address asset,
        address account,
        uint256 amount
    ) external;

    function stopMiningSupplyReward(
        address asset,
        address account,
        uint256 amount
    ) external;

    function startMiningBorrowReward(
        address asset,
        address account,
        uint256 amount
    ) external;

    function stopMiningBorrowReward(
        address asset,
        address account,
        uint256 amount
    ) external;
}
