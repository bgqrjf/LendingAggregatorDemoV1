// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

interface IPriceOracle{
    function getAssetPrice(address asset) external view returns (uint256);
    function setAssetPrice(address asset, uint price) external;

    function valueOfAsset(address asset, address quote, uint amount) external view returns(uint256);
}
