// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IRouter{
    function addAsset(Types.NewAssetParams memory _newAsset) external returns (Types.Asset memory asset);
    function updateConfig(address _config) external;
    function updateFactory(address _factory) external;
    function updateTreasury(address _treasury) external;
    function addProvider(address _provider) external;
    function removeProvider(uint _providerIndex, address _provider) external;
    function updatePriceOracle(address _priceOracle) external;
    function updateStrategy(address _strategy) external;

    function supply(address _underlying, address _to, bool _colletralable) external returns (uint sTokenAmount);
    function withdraw(address _underlying, address _to, bool _colletralable) external;
    function borrow(address _underlying, address _to) external returns (uint amount);
    function repay(address _underlying, address _for) external returns (uint amount);
    function liquidate(
        address _debtToken, 
        address _colletrallToken, 
        address _for, 
        address _to
    ) external returns (uint liquidateAmount, uint burnAmount);
    function getAssetByID(uint id) external view returns (ISToken, IDToken, bool, uint, uint);
    function totalSupplied(address _underlying) external view returns (uint amount);
    function totalDebts(address _underlying) external view returns (uint amount);
    function borrowCap(address _underlying, address _account) external view returns (uint);
    function valueOf(address _account, address _quote) external view returns (uint collateralValue, uint borrowingValue);

    // external state-getters
    function ETH() external view returns(address);
    function assets(address) external view returns(Types.Asset memory);
}
