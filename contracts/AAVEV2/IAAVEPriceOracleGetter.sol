// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

/**
 * @title IPriceOracleGetter
 * @author Aave
 * @notice Interface for the Aave price oracle.
 **/
interface IAAVEPriceOracleGetter {
    function getAssetPrice(address asset) external view returns (uint256);
}
