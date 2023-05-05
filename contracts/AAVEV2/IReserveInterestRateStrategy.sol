// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.18;

import "./ILendingPoolAddressesProvider.sol";

abstract contract IReserveInterestRateStrategy {
    /**
     * @dev this constant represents the utilization rate at which the pool aims to obtain most competitive borrow rates.
     * Expressed in ray
     **/
    uint256 public OPTIMAL_UTILIZATION_RATE;

    /**
     * @dev This constant represents the excess utilization rate above the optimal. It's always equal to
     * 1-optimal utilization rate. Added as a constant here for gas optimizations.
     * Expressed in ray
     **/

    uint256 public EXCESS_UTILIZATION_RATE;

    ILendingPoolAddressesProvider public addressesProvider;

    function variableRateSlope1() external view virtual returns (uint256);

    function variableRateSlope2() external view virtual returns (uint256);

    function stableRateSlope1() external view virtual returns (uint256);

    function stableRateSlope2() external view virtual returns (uint256);

    function baseVariableBorrowRate() external view virtual returns (uint256);

    function getMaxVariableBorrowRate() external view virtual returns (uint256);

    function calculateInterestRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    )
        external
        view
        virtual
        returns (
            uint256,
            uint256,
            uint256
        );
}
