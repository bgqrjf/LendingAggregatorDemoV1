// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

interface IPriceOracleGetter {
    function BASE_CURRENCY() external view returns (address);

    function BASE_CURRENCY_UNIT() external view returns (uint256);

    function getAssetPrice(address asset) external view returns (uint256);

    function valueOfAsset(address asset, address quote, uint amount) external view  returns(uint256);
}
