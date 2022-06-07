// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "./interfaces/IPriceOracleGetter.sol";

contract PriceOracle is IPriceOracleGetter {
    address public base;  
    uint256 public unit;
    mapping (address => uint256) public price;
    
    function BASE_CURRENCY() external view returns (address) {
        return base;
    }

  function BASE_CURRENCY_UNIT() external override view returns (uint256) {
      return unit;
  }

  function getAssetPrice(address asset) external view override  returns (uint256) {
      return price[asset]; 
  }

  function valueOfAsset(address asset, address quote, uint amount) external view override returns(uint256){
      return quote == base ? amount * price[asset] / unit : amount * price[quote] / price[asset];
  }
}