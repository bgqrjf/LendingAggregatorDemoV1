// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {AAVEDataTypes} from './AAVEDataTypes.sol';

/**
 * @title IReserveInterestRateStrategy
 * @author Aave
 * @notice Interface for the calculation of the interest rates
 */
interface IAAVEInterestRateStrategy {
  function OPTIMAL_USAGE_RATIO() external view returns(uint256);
  /**
   * @notice Returns the base variable borrow rate
   * @return The base variable borrow rate, expressed in ray
   **/
  function getBaseVariableBorrowRate() external view returns (uint256);

  /**
   * @notice Returns the maximum variable borrow rate
   * @return The maximum variable borrow rate, expressed in ray
   **/
  function getMaxVariableBorrowRate() external view returns (uint256);

  /**
   * @notice Calculates the interest rates depending on the reserve's state and configurations
   * @param params The parameters needed to calculate interest rates
   * @return liquidityRate The liquidity rate expressed in rays
   * @return stableBorrowRate The stable borrow rate expressed in rays
   * @return variableBorrowRate The variable borrow rate expressed in rays
   **/
  function calculateInterestRates(AAVEDataTypes.CalculateInterestRatesParams memory params)
    external
    view
    returns (
      uint256,
      uint256,
      uint256
    );

  /**
   * @notice Returns the variable rate slope below optimal usage ratio
   * @dev Its the variable rate when usage ratio > 0 and <= OPTIMAL_USAGE_RATIO
   * @return The variable rate slope
   **/
  function getVariableRateSlope1() external view returns (uint256);

  /**
   * @notice Returns the variable rate slope above optimal usage ratio
   * @dev Its the variable rate when usage ratio > OPTIMAL_USAGE_RATIO
   * @return The variable rate slope
   **/
  function getVariableRateSlope2() external view returns (uint256);
}
