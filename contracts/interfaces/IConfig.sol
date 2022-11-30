// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IConfig {
    event RouterSet(address oldRouter, address newRouter);
    event BorrowConfigSet(
        address indexed token,
        Types.BorrowConfig oldConfig,
        Types.BorrowConfig newConfig
    );
    event UserDebtAndCollateralSet(
        address account,
        uint256 oldUserDebtAndCollateral,
        uint256 newUserDebtAndCollateral
    );

    function setRouter(address _router) external;

    function setBorrowConfig(address _token, Types.BorrowConfig memory _config)
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
    function borrowConfigs(address)
        external
        view
        returns (Types.BorrowConfig memory);

    function userDebtAndCollateral(address) external view returns (uint256);
}
