// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";
import "./IRouter.sol";

interface IReservePool {
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
        address _borrowedBy,
        bool _executeNow
    ) external;

    function repay(Types.UserAssetParams memory _params, bool _executeNow)
        external;

    function executeRepayAndSupply(address _asset, uint256 _recordLoops)
        external;

    function lentAmounts(address _asset) external view returns (uint256);
}
