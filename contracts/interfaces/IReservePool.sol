// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../libraries/internals/Types.sol";
import "./IRouter.sol";

interface IReservePool {
    event PendingListUpdated(
        address asset,
        address to,
        uint256 amount,
        bool collateralable
    );

    event SupplyExecuted(address account);

    function supply(
        Types.UserAssetParams memory _params,
        bool _collateralable,
        bool _executeNow
    ) external;

    function redeem(
        Types.UserAssetParams memory _params,
        address _redeemFrom,
        bool _collateralable,
        bool _executeNow
    ) external;

    function borrow(
        Types.UserAssetParams memory _params,
        bool _executeNow
    ) external;

    function repay(
        Types.UserAssetParams memory _params,
        uint256 _totalBorrowed,
        bool _executeNow
    ) external;

    function executeRepayAndSupply(
        address _asset,
        uint256 _recordLoops
    ) external;

    function redeemedAmounts(address _asset) external view returns (uint256);

    function lentAmounts(address _asset) external view returns (uint256);

    function pendingRepayAmounts(
        address _asset
    ) external view returns (uint256);

    function setConfig(
        address _asset,
        uint256 _maxReserve,
        uint256 _executeSupplyThreshold
    ) external;

    function setMaxPendingRatio(uint256 _maxPendingRatio) external;
}
