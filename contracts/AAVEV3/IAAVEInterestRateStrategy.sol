// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {AAVEDataTypes} from "./AAVEDataTypes.sol";

interface IAAVEInterestRateStrategy {
    function OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO()
        external
        view
        returns (uint256);

    function MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO()
        external
        view
        returns (uint256);

    function MAX_EXCESS_USAGE_RATIO() external view returns (uint256);

    function OPTIMAL_USAGE_RATIO() external view returns (uint256);

    function getBaseVariableBorrowRate() external view returns (uint256);

    function getBaseStableBorrowRate() external view returns (uint256);

    function getMaxVariableBorrowRate() external view returns (uint256);

    function getVariableRateSlope1() external view returns (uint256);

    function getVariableRateSlope2() external view returns (uint256);

    function getStableRateSlope1() external view returns (uint256);

    function getStableRateSlope2() external view returns (uint256);

    function getStableRateExcessOffset() external view returns (uint256);

    function calculateInterestRates(
        AAVEDataTypes.CalculateInterestRatesParams memory params
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}
