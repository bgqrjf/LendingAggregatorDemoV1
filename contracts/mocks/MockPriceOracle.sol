// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "../interfaces/IPriceOracle.sol";
import "../libraries/TransferHelper.sol";

contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) public price;
    mapping(address => uint256) public units;

    function addAsset(address _asset, uint256 _decimals) external {
        units[_asset] = 10**_decimals;
    }

    function getAssetPrice(address _asset)
        external
        view
        override
        returns (uint256)
    {
        return price[_asset];
    }

    function setAssetPrice(address _asset, uint256 _price) external override {
        price[_asset] = _price;
    }

    function valueOfAsset(
        address _asset,
        address _quote,
        uint256 _amount
    ) external view override returns (uint256) {
        return
            (((_amount * price[_asset]) / units[_asset]) * units[_quote]) /
            price[_quote];
    }
}
