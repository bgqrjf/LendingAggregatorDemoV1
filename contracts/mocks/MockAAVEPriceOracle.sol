// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import  './aave-core/interfaces/IPoolAddressesProvider.sol';

// modified aaveOracle
contract MockAAVEPriceOracle {
  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
  address public immutable BASE_CURRENCY;
  uint256 public immutable BASE_CURRENCY_UNIT;

  mapping(address => uint) internal prices;

  constructor(
    IPoolAddressesProvider provider,
    address baseCurrency,
    uint256 baseCurrencyUnit
  ) {
    ADDRESSES_PROVIDER = provider;
    BASE_CURRENCY = baseCurrency;
    BASE_CURRENCY_UNIT = baseCurrencyUnit;
  }

  function getAssetPrice(address asset) public view returns (uint256) {
    if (asset == BASE_CURRENCY) {
      return BASE_CURRENCY_UNIT;
    }  else {
      return prices[asset];
    }
  }

  function getAssetsPrices(address[] calldata assets)
    external
    view
    returns (uint256[] memory)
  {
    uint256[] memory _prices = new uint256[](assets.length);
    for (uint256 i = 0; i < assets.length; i++) {
      _prices[i] = getAssetPrice(assets[i]);
    }
    return _prices;
  }

  function setAssetPrice(address asset, uint price) public{
    prices[asset] = price;
  }
}
