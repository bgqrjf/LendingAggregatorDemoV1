// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "../interfaces/IExOraclePriceData.sol";

contract MockPriceOracleOKC {
    mapping(address => uint256) public units;
    mapping(address => string) public assetSymbol;
    address public exOracleAddress;
    address public dataSource;

    constructor(address _oracle, address _dataSource) {
        exOracleAddress = _oracle;
        dataSource = _dataSource;
    }

    function addAsset(
        address _asset,
        uint256 _decimals,
        string memory symbol
    ) external {
        units[_asset] = 10**_decimals;
        assetSymbol[_asset] = symbol;
    }

    function getAssetPrice(address _asset) public view returns (uint256) {
        string memory priceType = assetSymbol[_asset];
        (uint256 value, ) = IExOraclePriceData(exOracleAddress).get(
            priceType,
            dataSource
        );
        value *= 100;
        return value;
    }

    function valueOfAsset(
        address _asset,
        address _quote,
        uint256 _amount
    ) external view returns (uint256) {
        uint256 priceAsset = getAssetPrice(_asset);
        uint256 priceQuote = getAssetPrice(_quote);
        return
            (((_amount * priceAsset) / units[_asset]) * units[_quote]) /
            priceQuote;
    }
}
