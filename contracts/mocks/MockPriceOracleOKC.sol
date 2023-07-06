// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

contract MockPriceOracleOKC {
    mapping(address => uint256) public units;
    mapping(address => string) public assetSymbol;
    mapping(address => uint256) public ratios;
    mapping(address => uint256) public assetPrice;

    address public exOracleAddress;
    address public dataSource;

    uint256 constant MILLION = 1000000;

    constructor(address _oracle, address _dataSource) {
        exOracleAddress = _oracle;
        dataSource = _dataSource;
    }

    function addAsset(
        address _asset,
        uint256 _decimals,
        string memory symbol
    ) external {
        units[_asset] = 10 ** _decimals;
        assetSymbol[_asset] = symbol;
        ratios[_asset] = MILLION;
    }

    function getAssetPrice(address _asset) public view returns (uint256) {
        if (assetPrice[_asset] != 0) {
            return assetPrice[_asset];
        }

        string memory priceType = assetSymbol[_asset];
        (uint256 value, ) = IExOraclePriceData(exOracleAddress).get(
            priceType,
            dataSource
        );
        value *= 100; // add 2 decimals as we are using 8 decimals
        return (value * ratios[_asset]) / MILLION;
    }

    function setAssetPrice(address _asset, uint _price) external {
        assetPrice[_asset] = _price;
    }

    function setAssetRatio(address _asset, uint256 _ratio) external {
        ratios[_asset] = _ratio;
    }

    function valueOfAsset(
        address _asset,
        address _quote,
        uint256 _amount
    ) external view returns (uint256) {
        uint256 priceAsset = getAssetPrice(_asset);
        uint256 priceQuote = getAssetPrice(_quote);
        return
            (_amount * priceAsset * units[_quote]) /
            (units[_asset] * priceQuote);
    }
}

interface IExOraclePriceData {
    function latestRoundData(
        string calldata priceType,
        address dataSource
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function get(
        string calldata priceType,
        address source
    ) external view returns (uint256 price, uint256 timestamp);

    function getOffchain(
        string calldata priceType,
        address source
    ) external view returns (uint256 price, uint256 timestamp);

    function getCumulativePrice(
        string calldata priceType,
        address source
    ) external view returns (uint256 cumulativePrice, uint32 timestamp);

    function lastResponseTime(address source) external view returns (uint256);
}
