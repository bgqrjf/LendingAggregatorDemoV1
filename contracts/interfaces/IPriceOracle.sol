// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IPriceOracle {
    function getAssetPrice(address asset) external view returns (uint256);

    function setAssetPrice(address asset, uint256 price) external;

    function valueOfAsset(
        address asset,
        address quote,
        uint256 amount
    ) external view returns (uint256);
}
