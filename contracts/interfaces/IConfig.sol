// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IConfig {
    event RouterSet(address oldRouter, address newRouter);
    event AssetConfigSet(
        address indexed token,
        Types.AssetConfig oldConfig,
        Types.AssetConfig newConfig
    );
    event UserDebtAndCollateralSet(
        address account,
        uint256 oldUserDebtAndCollateral,
        uint256 newUserDebtAndCollateral
    );

    function setRouter(address _router) external;

    function setAssetConfig(address _token, Types.AssetConfig memory _config)
        external;

    function setUsingAsCollateral(
        address _account,
        uint256 _reserveIndex,
        bool _usingAsCollateral
    ) external;

    function setBorrowing(
        address _account,
        uint256 _reserveIndex,
        bool _borrowing
    ) external;

    // external state-getters
    function assetConfigs(address)
        external
        view
        returns (Types.AssetConfig memory);

    function userDebtAndCollateral(address asset)
        external
        view
        returns (uint256 config);
}
