// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "./interfaces/IPriceOracle.sol";
import "./libraries/TransferHelper.sol";

contract PriceOracle is IPriceOracle {
    mapping (address => uint256) public price;
    uint constant public unit = 100000000;

    function getAssetPrice(address asset) external view override returns (uint256) {
        return price[asset]; 
    }

    function setAssetPrice(address _asset, uint _price) external override{
        price[_asset] = _price;
    }

    function valueOfAsset(address asset, address quote, uint amount) external view override returns(uint256){
        return amount * price[quote] / price[asset];
    }
}